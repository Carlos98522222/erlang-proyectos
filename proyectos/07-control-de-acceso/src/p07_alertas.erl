
-module(p07_alertas).
-behaviour(gen_server).

-export([
    start_link/0,
    reportar_robo/1,
    registrar_intento/1,
    listar/0
]).

-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-define(TABLA, p07_alertas_dets).
-define(ARCHIVO, "data/alertas.dets").
-define(VENTANA, 60000).
-define(LIMITE, 3).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

reportar_robo(Id) ->
    gen_server:call(?MODULE, {reportar_robo, Id}).

registrar_intento(Id) ->
    gen_server:call(?MODULE, {registrar_intento, Id}).

listar() ->
    gen_server:call(?MODULE, listar).

init([]) ->
    ok = filelib:ensure_dir(?ARCHIVO),
    case dets:open_file(?TABLA, [
        {file, ?ARCHIVO},
        {type, set}
    ]) of
        {ok, ?TABLA} ->
            {ok, #{}};
        {error, Reason} ->
            {stop, {error_abriendo_alertas, Reason}}
    end.

%% Reportar tarjeta robada y revocarla
handle_call({reportar_robo, Id}, _From, State) ->
    Alerta = #{
        id => erlang:unique_integer([positive, monotonic]),
        tipo => tarjeta_reportada_como_robada,
        tarjeta => Id,
        fecha => erlang:system_time(millisecond),
        estado => activa
    },

    ClaveIntentos = {intentos, Id},

    Resultado = case dets:insert(?TABLA, [
        {{robada, Id}, Alerta},
        {ClaveIntentos, []}
    ]) of
        ok ->
            case dets:sync(?TABLA) of
                ok ->
                    case p07_credenciales:revocar(Id) of
                        {ok, revocada, _} ->
                            p07_bitacora:registrar(Alerta),
                            {ok, tarjeta_bloqueada};
                        {ok, revocada} ->
                            p07_bitacora:registrar(Alerta),
                            {ok, tarjeta_bloqueada};
                        Error ->
                            {error, {error_revocando_credencial, Error}}
                    end;
                Error ->
                    {error, Error}
            end;
        Error ->
            {error, Error}
    end,

    {reply, Resultado, State};

%% Registrar cada intento
handle_call({registrar_intento, Id}, _From, State) ->
    Ahora = erlang:system_time(millisecond),
    Clave = {intentos, Id},

    Tiempos = case dets:lookup(?TABLA, Clave) of
        [{Clave, Lista}] -> Lista;
        [] -> []
    end,

    Recientes = [
        T || T <- Tiempos,
        Ahora - T =< ?VENTANA
    ],

    Nuevos = [Ahora | Recientes],

    Resultado = case dets:insert(?TABLA, {Clave, Nuevos}) of
        ok ->
            case dets:sync(?TABLA) of
                ok ->
                    procesar_intento(Id, Nuevos, Ahora);
                Error ->
                    {error, {error_guardando_intento, Error}}
            end;
        Error ->
            {error, {error_registrando_intento, Error}}
    end,

    {reply, Resultado, State};

%% Consultar alertas
handle_call(listar, _From, State) ->
    Alertas = dets:foldl(
        fun
            ({{robada, _}, A}, Acc) -> [A | Acc];
            ({{alerta, _}, A}, Acc) -> [A | Acc];
            (_, Acc) -> Acc
        end,
        [],
        ?TABLA
    ),

    {reply, lists:reverse(Alertas), State};

handle_call(_Request, _From, State) ->
    {reply, {error, solicitud_desconocida}, State}.

%% Procesar intento después de contar
procesar_intento(Id, Nuevos, Ahora) ->
    EsRobada = case dets:lookup(?TABLA, {robada, Id}) of
        [{{robada, Id}, AlertaEncontrada}] ->
            {true, AlertaEncontrada};
        [] ->
            false
    end,

    Cantidad = length(Nuevos),

    case Cantidad >= ?LIMITE of
        true ->
            generar_alerta_sospechosa(Id, Cantidad, Ahora);
        false ->
            ok
    end,

    case EsRobada of
        {true, AlertaBloqueo} ->
            {bloqueada, AlertaBloqueo};
        false when Cantidad >= ?LIMITE ->
            obtener_ultima_alerta(Id);
        false ->
            {ok, Cantidad}
    end.

%% Evitar duplicar alertas en la misma ventana
generar_alerta_sospechosa(Id, Cantidad, Ahora) ->
    ClaveControl = {alerta_intentos, Id},

    case dets:lookup(?TABLA, ClaveControl) of
        [{ClaveControl, FechaAnterior}]
                when Ahora - FechaAnterior =< ?VENTANA ->
            ok;

        _ ->
            Alerta = #{
                id => erlang:unique_integer([positive, monotonic]),
                tipo => intentos_sospechosos,
                tarjeta => Id,
                intentos => Cantidad,
                fecha => Ahora,
                estado => activa
            },

            case dets:insert(?TABLA, [
                {{alerta, maps:get(id, Alerta)}, Alerta},
                {ClaveControl, Ahora}
            ]) of
                ok ->
                    case dets:sync(?TABLA) of
                        ok ->
                            p07_bitacora:registrar(Alerta),
                            ok;
                        Error ->
                            {error, Error}
                    end;
                Error ->
                    {error, Error}
            end
    end.

%% Recuperar la alerta más reciente de la tarjeta
obtener_ultima_alerta(Id) ->
    Alertas = dets:foldl(
        fun
            ({{alerta, _}, #{tarjeta := Tarjeta} = A}, Acc)
                    when Tarjeta =:= Id ->
                [A | Acc];
            (_, Acc) ->
                Acc
        end,
        [],
        ?TABLA
    ),

    case lists:sort(
        fun(A, B) ->
            maps:get(fecha, A) >= maps:get(fecha, B)
        end,
        Alertas
    ) of
        [Alerta | _] ->
            {alerta, Alerta};
        [] ->
            {ok, 3}
    end.

handle_cast(_Message, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    dets:close(?TABLA),
    ok.

code_change(_OldVersion, State, _Extra) ->
    {ok, State}.
