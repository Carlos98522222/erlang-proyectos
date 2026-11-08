
-module(p07_http_handler).

-export([init/2]).

init(Req0, State) ->
    Path = cowboy_req:path(Req0),
    Method = cowboy_req:method(Req0),

    case {Method, Path} of
        {<<"GET">>, <<"/metrics">>} ->
            Req = cowboy_req:reply(
                200,
                #{<<"content-type">> => <<"text/plain; version=0.0.4; charset=utf-8">>},
                generar_metricas(),
                Req0
            ),
            {ok, Req, State};

        _ ->
            {Status, Response} = procesar_peticion(Method, Path, Req0),
            Req = cowboy_req:reply(
                Status,
                #{<<"content-type">> => <<"application/json">>},
                jsx:encode(normalizar_json(Response)),
                Req0
            ),
            {ok, Req, State}
    end.

%% Metricas Prometheus
generar_metricas() ->
    Puertas = length(p07_puertas_sup:listar_puertas()),
    Credenciales = p07_credenciales:listar(),
    TotalCredenciales = length(Credenciales),
    Revocadas = length([
        C || C <- Credenciales,
        maps:get(estado, C, activa) =:= revocada
    ]),
    Personas = length(p07_personas_dentro:personas_dentro()),
    Eventos = p07_bitacora:total(),
    Alertas = length(p07_alertas:listar()),

    iolist_to_binary([
        "# HELP control_acceso_puertas_activas Numero de puertas activas\n",
        "# TYPE control_acceso_puertas_activas gauge\n",
        io_lib:format("control_acceso_puertas_activas ~B~n", [Puertas]),

        "# HELP control_acceso_credenciales_total Credenciales registradas\n",
        "# TYPE control_acceso_credenciales_total gauge\n",
        io_lib:format("control_acceso_credenciales_total ~B~n", [TotalCredenciales]),

        "# HELP control_acceso_credenciales_revocadas Credenciales revocadas\n",
        "# TYPE control_acceso_credenciales_revocadas gauge\n",
        io_lib:format("control_acceso_credenciales_revocadas ~B~n", [Revocadas]),

        "# HELP control_acceso_personas_dentro Personas dentro del edificio\n",
        "# TYPE control_acceso_personas_dentro gauge\n",
        io_lib:format("control_acceso_personas_dentro ~B~n", [Personas]),

        "# HELP control_acceso_eventos_total Eventos almacenados en bitacora\n",
        "# TYPE control_acceso_eventos_total gauge\n",
        io_lib:format("control_acceso_eventos_total ~B~n", [Eventos]),

        "# HELP control_acceso_alertas_total Alertas registradas\n",
        "# TYPE control_acceso_alertas_total gauge\n",
        io_lib:format("control_acceso_alertas_total ~B~n", [Alertas])
    ]).

%% Diagnostico con Recon
generar_diagnostico() ->
    ProcesosMemoria = recon:proc_count(memory, 10),
    ProcesosCola = recon:proc_count(message_queue_len, 10),
    Memoria = erlang:memory(),
    #{
        procesos_totales => erlang:system_info(process_count),
        procesos_maximos => erlang:system_info(process_limit),
        memoria_total_bytes => proplists:get_value(total, Memoria, 0),
        memoria_procesos_bytes => proplists:get_value(processes, Memoria, 0),
        memoria_binarios_bytes => proplists:get_value(binary, Memoria, 0),
        memoria_ets_bytes => proplists:get_value(ets, Memoria, 0),
        procesos_mayor_memoria => [
            diagnostico_proceso(P) || P <- ProcesosMemoria
        ],
        procesos_mayor_cola => [
            diagnostico_proceso(P) || P <- ProcesosCola
        ]
    }.

diagnostico_proceso({Pid, Valor, Informacion}) ->
    #{
        pid => list_to_binary(pid_to_list(Pid)),
        valor => Valor,
        nombre => proplists:get_value(registered_name, Informacion, undefined),
        funcion => io_lib:format(
            "~p",
            [proplists:get_value(current_function, Informacion, undefined)]
        )
    }.

%% Estado general
procesar_peticion(<<"GET">>, <<"/api/diagnostico">>, _Req) ->
    {200, generar_diagnostico()};

procesar_peticion(<<"GET">>, <<"/api/estado">>, _Req) ->
    {200, #{
        sistema => <<"Control de Acceso">>,
        estado => <<"activo">>,
        puertas => length(p07_puertas_sup:listar_puertas()),
        credenciales => length(p07_credenciales:listar()),
        eventos => p07_bitacora:total()
    }};

%% Consultar puertas
procesar_peticion(<<"GET">>, <<"/api/puertas">>, _Req) ->
    PuertasRegistradas = p07_puertas_sup:listar_puertas(),
    Puertas = [
        begin
            Estado = p07_puerta:estado(Pid),
            #{
                id => maps:get(id, Estado),
                estado => maps:get(estado, Estado),
                actualizado_en => maps:get(actualizado_en, Estado)
            }
        end
        || {{puerta, _Id}, Pid, _Tipo, _Modulos} <- PuertasRegistradas,
           is_pid(Pid)
    ],
    {200, #{
        total => length(Puertas),
        puertas => lists:sort(
            fun(A, B) -> maps:get(id, A) =< maps:get(id, B) end,
            Puertas
        )
    }};

%% Abrir o cerrar puertas
procesar_peticion(
    <<"POST">>,
    <<"/api/puertas/", Resto/binary>>,
    _Req
) ->
    case binary:split(Resto, <<"/">>, [global]) of
        [IdBin, <<"abrir">>] -> controlar_puerta(abrir, IdBin);
        [IdBin, <<"cerrar">>] -> controlar_puerta(cerrar, IdBin);
        _ -> {404, #{error => <<"Ruta de puerta invalida">>}}
    end;

%% Consultar credenciales
procesar_peticion(<<"GET">>, <<"/api/credenciales">>, _Req) ->
    Credenciales = p07_credenciales:listar(),
    {200, #{total => length(Credenciales), credenciales => Credenciales}};

%% Consultar alertas
procesar_peticion(<<"GET">>, <<"/api/alertas">>, _Req) ->
    Alertas = p07_alertas:listar(),
    {200, #{total => length(Alertas), alertas => Alertas}};

%% Reportar tarjeta robada
procesar_peticion(<<"POST">>, <<"/api/tarjetas/robada">>, Req) ->
    case cowboy_req:read_body(Req) of
        {ok, Body, _Req} ->
            try jsx:decode(Body, [return_maps]) of
                Datos ->
                    Id = maps:get(
                        <<"tarjeta">>,
                        Datos,
                        maps:get(<<"credencial">>, Datos, undefined)
                    ),
                    case Id of
                        undefined ->
                            {400, #{error => <<"Falta el identificador de la tarjeta">>}};
                        _ ->
                            case p07_alertas:reportar_robo(Id) of
                                {ok, tarjeta_bloqueada} ->
                                    {200, #{
                                        resultado => <<"tarjeta_bloqueada">>,
                                        tarjeta => Id,
                                        mensaje => <<"Tarjeta reportada y bloqueada correctamente">>
                                    }};
                                Otro ->
                                    {500, #{
                                        error => <<"No se pudo reportar la tarjeta">>,
                                        detalle => io_lib:format("~p", [Otro])
                                    }}
                            end
                    end
            catch
                _:_ -> {400, #{error => <<"Solicitud JSON invalida">>}}
            end;
        _ -> {400, #{error => <<"No se pudo leer la solicitud">>}}
    end;

%% Registrar intento de acceso
procesar_peticion(<<"POST">>, <<"/api/accesos">>, Req) ->
    case cowboy_req:read_body(Req) of
        {ok, Body, _Req} ->
            try jsx:decode(Body, [return_maps]) of
                Datos ->
                    PuertaId = maps:get(<<"puerta">>, Datos),
                    Credencial = maps:get(<<"credencial">>, Datos),
                    case obtener_puerta(PuertaId) of
                        {ok, Pid} -> procesar_intento_acceso(Pid, Credencial);
                        error -> {404, #{error => <<"Puerta no encontrada">>}}
                    end
            catch
                _:_ -> {400, #{error => <<"Solicitud JSON invalida">>}}
            end;
        _ -> {400, #{error => <<"No se pudo leer la solicitud">>}}
    end;

%% Revocar credencial
procesar_peticion(
    <<"POST">>,
    <<"/api/credenciales/", _/binary>>,
    Req
) ->
    case cowboy_req:binding(id, Req) of
        undefined ->
            {400, #{error => <<"Identificador invalido">>}};
        Id ->
            case p07_credenciales:revocar(Id) of
                {ok, revocada} -> respuesta_revocacion(Id);
                {ok, revocada, _Distribucion} -> respuesta_revocacion(Id);
                {error, credencial_no_encontrada} ->
                    {404, #{error => <<"Credencial no encontrada">>}};
                Otro ->
                    {500, #{
                        error => <<"Error al revocar credencial">>,
                        detalle => io_lib:format("~p", [Otro])
                    }}
            end
    end;

%% Consultar bitacora
procesar_peticion(<<"GET">>, <<"/api/bitacora">>, _Req) ->
    Eventos = p07_bitacora:listar(),
    {200, #{total => length(Eventos), eventos => Eventos}};

procesar_peticion(_Method, _Path, _Req) ->
    {404, #{error => <<"Ruta no encontrada">>}}.

procesar_intento_acceso(Pid, Credencial) ->
    case p07_alertas:registrar_intento(Credencial) of
        {bloqueada, Alerta} ->
            {403, #{
                resultado => <<"denegado">>,
                motivo => <<"tarjeta_reportada_como_robada">>,
                alerta => Alerta,
                mensaje => <<"Acceso rechazado: tarjeta reportada como robada">>
            }};
        {alerta, Alerta} ->
            ejecutar_acceso(Pid, Credencial, Alerta);
        {ok, _Cantidad} ->
            ejecutar_acceso(Pid, Credencial, undefined);
        Otro ->
            {500, #{
                error => <<"No se pudo verificar el intento">>,
                detalle => io_lib:format("~p", [Otro])
            }}
    end.

ejecutar_acceso(Pid, Credencial, Alerta) ->
    case p07_acceso:intentar(Pid, Credencial) of
        {ok, acceso_permitido, EventoId} ->
            {200, #{
                evento => EventoId,
                resultado => <<"permitido">>,
                alerta => Alerta,
                mensaje => <<"Acceso autorizado">>
            }};
        {error, acceso_denegado, Motivo} ->
            {403, #{resultado => <<"denegado">>, motivo => Motivo, alerta => Alerta}};
        {error, acceso_denegado, Motivo, EventoId} ->
            {403, #{
                evento => EventoId,
                resultado => <<"denegado">>,
                motivo => Motivo,
                alerta => Alerta
            }};
        Otro ->
            {500, #{
                error => <<"Respuesta inesperada al procesar acceso">>,
                detalle => io_lib:format("~p", [Otro])
            }}
    end.

respuesta_revocacion(Id) ->
    {200, #{
        resultado => <<"revocada">>,
        credencial => Id,
        mensaje => <<"Credencial revocada correctamente">>
    }}.

controlar_puerta(Accion, IdBin) ->
    try binary_to_integer(IdBin) of
        PuertaId ->
            case obtener_puerta(PuertaId) of
                {ok, Pid} -> ejecutar_control(Accion, PuertaId, Pid);
                error -> {404, #{error => <<"Puerta no encontrada">>}}
            end
    catch
        _:_ -> {400, #{error => <<"Identificador de puerta invalido">>}}
    end.

ejecutar_control(abrir, PuertaId, Pid) ->
    case p07_puerta:abrir(Pid) of
        {ok, abierta} ->
            registrar_control(PuertaId, apertura_manual, <<"Puerta abierta correctamente">>);
        {error, ya_abierta} ->
            {409, #{error => <<"La puerta ya esta abierta">>}};
        {error, puerta_forzada} ->
            {409, #{error => <<"La puerta esta forzada y no puede abrirse normalmente">>}};
        Otro ->
            {500, #{error => <<"No se pudo abrir la puerta">>, detalle => io_lib:format("~p", [Otro])}}
    end;

ejecutar_control(cerrar, PuertaId, Pid) ->
    case p07_puerta:cerrar(Pid) of
        {ok, cerrada} ->
            registrar_control(PuertaId, cierre_manual, <<"Puerta cerrada correctamente">>);
        Otro ->
            {500, #{error => <<"No se pudo cerrar la puerta">>, detalle => io_lib:format("~p", [Otro])}}
    end.

registrar_control(PuertaId, Tipo, Mensaje) ->
    case p07_bitacora:registrar(#{tipo => Tipo, puerta => PuertaId}) of
        {ok, EventoId} ->
            {200, #{
                resultado => <<"correcto">>,
                puerta => PuertaId,
                evento => EventoId,
                mensaje => Mensaje
            }};
        Error ->
            {500, #{
                error => <<"La accion se ejecuto, pero no se pudo registrar en bitacora">>,
                detalle => io_lib:format("~p", [Error])
            }}
    end.

obtener_puerta(PuertaId) ->
    case lists:keyfind({puerta, PuertaId}, 1, p07_puertas_sup:listar_puertas()) of
        {{puerta, PuertaId}, Pid, _Tipo, _Modulos} when is_pid(Pid) ->
            {ok, Pid};
        _ -> error
    end.

normalizar_json(Mapa) when is_map(Mapa) ->
    maps:from_list([
        {normalizar_json(K), normalizar_json(V)}
        || {K, V} <- maps:to_list(Mapa)
    ]);

normalizar_json(Lista)
        when is_list(Lista),
             Lista =/= [],
             is_integer(hd(Lista)) ->
    case io_lib:printable_unicode_list(Lista) of
        true -> unicode:characters_to_binary(Lista);
        false -> [normalizar_json(Elemento) || Elemento <- Lista]
    end;

normalizar_json(Lista) when is_list(Lista) ->
    [normalizar_json(Elemento) || Elemento <- Lista];

normalizar_json(Valor) when is_atom(Valor) ->
    atom_to_binary(Valor, utf8);

normalizar_json(Valor) when is_tuple(Valor) ->
    list_to_binary(io_lib:format("~p", [Valor]));

normalizar_json(Valor) ->
    Valor.
