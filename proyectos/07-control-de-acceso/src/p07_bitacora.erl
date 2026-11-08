
-module(p07_bitacora).
-behaviour(gen_server).

-export([
    start_link/0,
    registrar/1,
    registrar/2,
    listar/0,
    total/0
]).

-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-define(TABLA, p07_bitacora_tabla).
-define(ARCHIVO, "data/bitacora.dets").

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

registrar(Evento) ->
    gen_server:call(?MODULE, {registrar, Evento}).

registrar(IdOrigen, Evento) ->
    gen_server:call(?MODULE, {registrar, IdOrigen, Evento}).

listar() ->
    gen_server:call(?MODULE, listar).

total() ->
    gen_server:call(?MODULE, total).

init([]) ->
    ok = filelib:ensure_dir(?ARCHIVO),

    case dets:open_file(?TABLA, [
        {file, ?ARCHIVO},
        {type, set}
    ]) of
        {ok, ?TABLA} ->
            logger:info("Bitacora iniciada"),
            {ok, #{tabla => ?TABLA}};

        {error, Reason} ->
            {stop, {error_abriendo_bitacora, Reason}}
    end.

handle_call({registrar, IdOrigen, Evento}, _From, State) ->
    Clave = {origen, IdOrigen},

    case dets:lookup(?TABLA, Clave) of
        [{Clave, IdExistente}] ->
            {reply, {ok, IdExistente, duplicado}, State};

        [] ->
            Id = erlang:unique_integer([positive, monotonic]),
            Registro = #{
                id => Id,
                id_origen => IdOrigen,
                evento => Evento,
                fecha => erlang:system_time(millisecond)
            },

            case dets:insert(?TABLA, [
                {Id, Registro},
                {Clave, Id}
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

handle_call({registrar, Evento}, _From, State) ->
    Id = erlang:unique_integer([positive, monotonic]),
    Registro = #{
        id => Id,
        evento => Evento,
        fecha => erlang:system_time(millisecond)
    },

    case dets:insert(?TABLA, {Id, Registro}) of
        ok ->
            case dets:sync(?TABLA) of
                ok -> {reply, {ok, Id}, State};
                Error -> {reply, {error, Error}, State}
            end;
        Error ->
            {reply, {error, Error}, State}
    end;

handle_call(listar, _From, State) ->
    Eventos = [
        Registro
        || {_Clave, Registro} <- dets:match_object(
            ?TABLA,
            {'_', #{id => '_', evento => '_', fecha => '_'}}
        )
    ],

    Ordenados = lists:sort(
        fun(A, B) -> maps:get(id, A) =< maps:get(id, B) end,
        Eventos
    ),

    {reply, Ordenados, State};

handle_call(total, _From, State) ->
    Registros = dets:match_object(
        ?TABLA,
        {'_', #{id => '_', evento => '_', fecha => '_'}}
    ),
    {reply, length(Registros), State};

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
