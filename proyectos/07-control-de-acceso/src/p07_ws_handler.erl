
-module(p07_ws_handler).

-behaviour(cowboy_websocket).

-export([
    init/2,
    websocket_init/1,
    websocket_handle/2,
    websocket_info/2,
    terminate/3
]).

init(Req, _State) ->
    {cowboy_websocket, Req, #{}}.

websocket_init(State) ->
    self() ! actualizar,
    {ok, State}.

websocket_handle({text, <<"ping">>}, State) ->
    {reply, {text, <<"pong">>}, State};

websocket_handle(_Frame, State) ->
    {ok, State}.

websocket_info(actualizar, State) ->
    Datos = obtener_estado(),
    Mensaje = jsx:encode(Datos),
    erlang:send_after(5000, self(), actualizar),
    {reply, {text, Mensaje}, State};

websocket_info(_Info, State) ->
    {ok, State}.

terminate(_Reason, _PartialReq, _State) ->
    ok.

obtener_estado() ->
    #{
        tipo => actualizacion,
        puertas => length(p07_puertas_sup:listar_puertas()),
        credenciales => length(p07_credenciales:listar()),
        personas_dentro => length(p07_personas_dentro:personas_dentro()),
        eventos => p07_bitacora:total(),
        alertas => length(p07_alertas:listar()),
        timestamp => erlang:system_time(second)
    }.
