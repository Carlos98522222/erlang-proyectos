
-module(p07_puerta).
-behaviour(gen_server).

-export([
    start_link/1,
    abrir/1,
    cerrar/1,
    forzar/1,
    estado/1,
    sincronizar_credenciales/2,
    actualizar_credencial/2,
    validar_local/2
]).

-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

start_link(Id) ->
    gen_server:start_link(?MODULE, [Id], []).

abrir(Pid) -> gen_server:call(Pid, abrir).
cerrar(Pid) -> gen_server:call(Pid, cerrar).
forzar(Pid) -> gen_server:call(Pid, forzar).
estado(Pid) -> gen_server:call(Pid, estado).

sincronizar_credenciales(Pid, Credenciales) ->
    gen_server:call(Pid, {sincronizar_credenciales, Credenciales}).

actualizar_credencial(Pid, Credencial) ->
    gen_server:call(Pid, {actualizar_credencial, Credencial}).

validar_local(Pid, CredencialId) ->
    gen_server:call(Pid, {validar_local, CredencialId}).

init([Id]) ->
    self() ! cargar_credenciales,
    {ok, #{
        id => Id,
        estado => cerrada,
        credenciales_locales => #{},
        actualizado_en => erlang:system_time(millisecond)
    }}.

handle_call(estado, _From, State) ->
    {reply, State, State};

handle_call({sincronizar_credenciales, Credenciales}, _From, State) ->
    Mapa = maps:from_list([
        {maps:get(id, C), C}
        || C <- Credenciales,
           maps:get(estado, C, revocada) =:= activa
    ]),
    NuevoEstado = State#{credenciales_locales => Mapa},
    {reply, {ok, maps:size(Mapa)}, NuevoEstado};

handle_call({actualizar_credencial, Credencial}, _From, State) ->
    Id = maps:get(id, Credencial),
    Credenciales = maps:get(credenciales_locales, State),

    NuevasCredenciales =
        case maps:get(estado, Credencial, revocada) of
            activa -> maps:put(Id, Credencial, Credenciales);
            revocada -> maps:remove(Id, Credenciales)
        end,

    {reply, ok, State#{credenciales_locales => NuevasCredenciales}};

handle_call({validar_local, CredencialId}, _From, State) ->
    Credenciales = maps:get(credenciales_locales, State),
    Resultado = case maps:find(CredencialId, Credenciales) of
        {ok, Credencial} -> {ok, Credencial};
        error -> {error, credencial_no_autorizada_localmente}
    end,
    {reply, Resultado, State};

handle_call(abrir, _From, #{estado := forzada} = State) ->
    {reply, {error, puerta_forzada}, State};

handle_call(abrir, _From, #{estado := abierta} = State) ->
    {reply, {error, ya_abierta}, State};

handle_call(abrir, _From, State) ->
    NuevoEstado = State#{
        estado => abierta,
        actualizado_en => erlang:system_time(millisecond)
    },
    {reply, {ok, abierta}, NuevoEstado};

handle_call(cerrar, _From, State) ->
    NuevoEstado = State#{
        estado => cerrada,
        actualizado_en => erlang:system_time(millisecond)
    },
    {reply, {ok, cerrada}, NuevoEstado};

handle_call(forzar, _From, State) ->
    NuevoEstado = State#{
        estado => forzada,
        actualizado_en => erlang:system_time(millisecond)
    },
    {reply, {ok, forzada}, NuevoEstado};

handle_call(_Request, _From, State) ->
    {reply, {error, solicitud_desconocida}, State}.

handle_cast(_Message, State) ->
    {noreply, State}.

handle_info(cargar_credenciales, State) ->
    case catch p07_credenciales:listar() of
        Credenciales when is_list(Credenciales) ->
            Mapa = maps:from_list([
                {maps:get(id, C), C}
                || C <- Credenciales,
                   maps:get(estado, C, revocada) =:= activa
            ]),
            {noreply, State#{credenciales_locales => Mapa}};
        _ ->
            {noreply, State}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVersion, State, _Extra) ->
    {ok, State}.
