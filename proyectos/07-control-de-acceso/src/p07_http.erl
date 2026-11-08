
-module(p07_http).

-behaviour(gen_server).

-export([start_link/0]).

-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    case application:ensure_all_started(cowboy) of
        {ok, _Aplicaciones} ->
            iniciar_servidor_http();
        {error, Razon} ->
            {stop, {error_iniciando_cowboy, Razon}}
    end.

iniciar_servidor_http() ->
    Dispatch = cowboy_router:compile([
        {'_', [
            {"/ws", p07_ws_handler, []},
            {"/metrics", p07_http_handler, []},
            {"/api/diagnostico", p07_http_handler, []},
            {"/api/estado", p07_http_handler, []},
            {"/api/puertas", p07_http_handler, []},
            {"/api/puertas/:id/abrir", p07_http_handler, []},
            {"/api/puertas/:id/cerrar", p07_http_handler, []},
            {"/api/accesos", p07_http_handler, []},
            {"/api/bitacora", p07_http_handler, []},
            {"/api/credenciales", p07_http_handler, []},
            {"/api/credenciales/:id/revocar", p07_http_handler, []},
            {"/api/alertas", p07_http_handler, []},
            {"/api/tarjetas/robada", p07_http_handler, []},
            {"/", cowboy_static,
                {priv_file, p07_control_de_acceso, "www/index.html"}},
            {"/[...]", cowboy_static,
                {priv_dir, p07_control_de_acceso, "www"}}
        ]}
    ]),

    case cowboy:start_clear(
        http_listener,
        [{port, 8080}],
        #{env => #{dispatch => Dispatch}}
    ) of
        {ok, _Pid} ->
            logger:info("Servidor HTTP iniciado en puerto 8080"),
            {ok, #{puerto => 8080}};
        {error, Razon} ->
            {stop, {error_iniciando_http, Razon}}
    end.

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Message, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    catch cowboy:stop_listener(http_listener),
    ok.

code_change(_OldVersion, State, _Extra) ->
    {ok, State}.
