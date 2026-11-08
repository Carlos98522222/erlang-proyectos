-module(p07_credenciales).
-behaviour(gen_server).

-export([
    start_link/0,
    registrar/2,
    registrar_lote/1,
    validar/1,
    revocar/1,
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

-define(TABLA, p07_credenciales_dets).
-define(ARCHIVO, "data/credenciales.dets").

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

registrar(Id, Persona) ->
    gen_server:call(?MODULE, {registrar, Id, Persona}).

registrar_lote(Personas) ->
    gen_server:call(?MODULE, {registrar_lote, Personas}, infinity).

validar(Id) ->
    gen_server:call(?MODULE, {validar, Id}).

revocar(Id) ->
    gen_server:call(?MODULE, {revocar, Id}).

listar() ->
    gen_server:call(?MODULE, listar).

init([]) ->
    ok = filelib:ensure_dir(?ARCHIVO),
    case dets:open_file(?TABLA, [{file, ?ARCHIVO}, {type, set}]) of
        {ok, ?TABLA} ->
            logger:info("Almacenamiento persistente de credenciales iniciado"),
            {ok, #{tabla => ?TABLA}};
        {error, Reason} ->
            {stop, {error_abriendo_credenciales, Reason}}
    end.

handle_call({registrar, Id, Persona}, _From, State) ->
    Credencial = #{
        id => Id,
        persona => Persona,
        estado => activa,
        creada_en => erlang:system_time(millisecond)
    },
    case dets:insert_new(?TABLA, {Id, Credencial}) of
        true ->
            case dets:sync(?TABLA) of
                ok ->
                    Distribucion =
                        p07_puertas_sup:distribuir_credencial(Credencial),
                    {reply, {ok, registrada, Distribucion}, State};
                Error ->
                    {reply, {error, Error}, State}
            end;
        false ->
            {reply, {error, ya_existe}, State}
    end;

handle_call({registrar_lote, Personas}, _From, State)
        when is_list(Personas) ->
    Ahora = erlang:system_time(millisecond),
    Credenciales = [
        #{
            id => Id,
            persona => Persona,
            estado => activa,
            creada_en => Ahora
        }
        || {Id, Persona} <- Personas
    ],
    Registros = [
        {maps:get(id, C), C}
        || C <- Credenciales
    ],
    case dets:insert(?TABLA, Registros) of
        ok ->
            case dets:sync(?TABLA) of
                ok ->
                    {reply,
                     {ok, length(Credenciales), sincronizacion_pendiente},
                     State};
                Error ->
                    {reply, {error, Error}, State}
            end;
        Error ->
            {reply, {error, Error}, State}
    end;

handle_call({validar, Id}, _From, State) ->
    Resultado =
        case dets:lookup(?TABLA, Id) of
            [{Id, #{estado := activa} = Credencial}] ->
                {ok, Credencial};
            [{Id, #{estado := revocada}}] ->
                {error, credencial_revocada};
            [] ->
                {error, credencial_no_encontrada}
        end,
    {reply, Resultado, State};

handle_call({revocar, Id}, _From, State) ->
    Resultado =
        case dets:lookup(?TABLA, Id) of
            [{Id, Credencial}] ->
                Nueva = Credencial#{
                    estado => revocada,
                    revocada_en => erlang:system_time(millisecond)
                },
                case dets:insert(?TABLA, {Id, Nueva}) of
                    ok ->
                        case dets:sync(?TABLA) of
                            ok ->
                                Distribucion =
                                    p07_puertas_sup:distribuir_credencial(Nueva),
                                {ok, revocada, Distribucion};
                            Error ->
                                {error, Error}
                        end;
                    Error ->
                        {error, Error}
                end;
            [] ->
                {error, credencial_no_encontrada}
        end,
    {reply, Resultado, State};

handle_call(listar, _From, State) ->
    Credenciales = [
        Credencial
        || {_Id, Credencial} <-
            dets:match_object(?TABLA, {'_', '_'})
    ],
    {reply, Credenciales, State};

handle_call(_Request, _From, State) ->
    {reply, {error, solicitud_desconocida}, State}.

handle_cast(_Message, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    dets:close(?TABLA),
    ok.

code_change(_OldVersion, State, _Extra) ->
    {ok, State}.
