
-module(p07_personas_dentro).
-behaviour(gen_server).

-export([
    start_link/0,
    registrar_entrada/3,
    registrar_salida/1,
    personas_dentro/0,
    eventos_pendientes/0,
    confirmar_eventos/1,
    sincronizar_bitacora/0
]).

-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-define(TABLA, p07_personas_dentro_dets).
-define(ARCHIVO, "data/personas_dentro.dets").

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

registrar_entrada(CredencialId, Persona, Evento) ->
    gen_server:call(?MODULE, {registrar_entrada, CredencialId, Persona, Evento}).

registrar_salida(CredencialId) ->
    gen_server:call(?MODULE, {registrar_salida, CredencialId}).

personas_dentro() ->
    gen_server:call(?MODULE, personas_dentro).

eventos_pendientes() ->
    gen_server:call(?MODULE, eventos_pendientes).

confirmar_eventos(Ids) ->
    gen_server:call(?MODULE, {confirmar_eventos, Ids}).

sincronizar_bitacora() ->
    gen_server:call(?MODULE, sincronizar_bitacora, 30000).

init([]) ->
    ok = filelib:ensure_dir(?ARCHIVO),
    case dets:open_file(?TABLA, [{file, ?ARCHIVO}, {type, set}]) of
        {ok, ?TABLA} ->
            logger:info("Control local persistente iniciado"),
            {ok, #{tabla => ?TABLA}};
        {error, Reason} ->
            {stop, {error_abriendo_control_local, Reason}}
    end.

nuevo_id_evento() ->
    {erlang:system_time(microsecond),
     erlang:unique_integer([positive, monotonic])}.

handle_call(
    {registrar_entrada, CredencialId, Persona, Evento},
    _From,
    State
) ->
    case dets:lookup(?TABLA, {persona, CredencialId}) of
        [{_, _}] ->
            {reply, {error, anti_passback}, State};
        [] ->
            Id = nuevo_id_evento(),
            Registro = #{
                id => Id,
                evento => Evento,
                fecha => erlang:system_time(millisecond)
            },
            case dets:insert(?TABLA, [
                {{persona, CredencialId}, Persona},
                {{evento, Id}, Registro}
            ]) of
                ok ->
                    case dets:sync(?TABLA) of
                        ok -> {reply, {ok, Id}, State};
                        Error -> {reply, {error, Error}, State}
                    end;
                Error ->
                    {reply, {error, Error}, State}
            end
    end;

handle_call({registrar_salida, CredencialId}, _From, State) ->
    case dets:lookup(?TABLA, {persona, CredencialId}) of
        [{{persona, CredencialId}, Persona}] ->
            Id = nuevo_id_evento(),
            Evento = #{
                tipo => salida_registrada,
                tarjeta => CredencialId,
                persona => Persona
            },
            Registro = #{
                id => Id,
                evento => Evento,
                fecha => erlang:system_time(millisecond)
            },
            case dets:insert(?TABLA, {{evento, Id}, Registro}) of
                ok ->
                    case dets:sync(?TABLA) of
                        ok ->
                            case dets:delete(?TABLA, {persona, CredencialId}) of
                                ok ->
                                    case dets:sync(?TABLA) of
                                        ok -> {reply, {ok, Id}, State};
                                        Error -> {reply, {error, Error}, State}
                                    end;
                                Error -> {reply, {error, Error}, State}
                            end;
                        Error -> {reply, {error, Error}, State}
                    end;
                Error ->
                    {reply, {error, Error}, State}
            end;
        [] ->
            {reply, {error, persona_no_registrada}, State}
    end;

handle_call(personas_dentro, _From, State) ->
    Personas = dets:foldl(
        fun
            ({{persona, CredencialId}, Persona}, Acc) ->
                [{CredencialId, Persona} | Acc];
            (_, Acc) ->
                Acc
        end,
        [],
        ?TABLA
    ),
    {reply, Personas, State};

handle_call(eventos_pendientes, _From, State) ->
    Eventos = obtener_eventos(),
    {reply, Eventos, State};

handle_call({confirmar_eventos, Ids}, _From, State) ->
    lists:foreach(
        fun(Id) -> dets:delete(?TABLA, {evento, Id}) end,
        Ids
    ),
    case dets:sync(?TABLA) of
        ok -> {reply, ok, State};
        Error -> {reply, {error, Error}, State}
    end;

handle_call(sincronizar_bitacora, _From, State) ->
    Resultado = sincronizar_eventos(obtener_eventos(), []),
    {reply, Resultado, State};

handle_call(_Request, _From, State) ->
    {reply, {error, solicitud_desconocida}, State}.

obtener_eventos() ->
    Eventos = dets:foldl(
        fun
            ({{evento, _Id}, Registro}, Acc) ->
                [Registro | Acc];
            (_, Acc) ->
                Acc
        end,
        [],
        ?TABLA
    ),
    lists:sort(
        fun(A, B) -> maps:get(id, A) =< maps:get(id, B) end,
        Eventos
    ).

sincronizar_eventos([], Sincronizados) ->
    {ok, lists:reverse(Sincronizados)};

sincronizar_eventos([Registro | Resto], Sincronizados) ->
    Id = maps:get(id, Registro),
    Evento = maps:get(evento, Registro),

    case p07_bitacora:registrar(Id, Evento) of
        {ok, _IdCentral} ->
            confirmar_y_continuar(Id, Resto, Sincronizados);
        {ok, _IdCentral, duplicado} ->
            confirmar_y_continuar(Id, Resto, Sincronizados);
        Error ->
            {error, {sincronizacion_fallida, Id, Error}}
    end.

confirmar_y_continuar(Id, Resto, Sincronizados) ->
    case dets:delete(?TABLA, {evento, Id}) of
        ok ->
            case dets:sync(?TABLA) of
                ok ->
                    sincronizar_eventos(Resto, [Id | Sincronizados]);
                Error ->
                    {error, {error_guardando_confirmacion, Id, Error}}
            end;
        Error ->
            {error, {error_eliminando_evento, Id, Error}}
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
