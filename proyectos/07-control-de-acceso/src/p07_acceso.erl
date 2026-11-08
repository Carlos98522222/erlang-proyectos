
-module(p07_acceso).

-export([
    intentar/2,
    registrar_salida/1,
    personas_dentro/0
]).

%% Intentar ingresar utilizando la credencial local de la puerta
intentar(PuertaPid, CredencialId) ->
    EstadoPuerta = p07_puerta:estado(PuertaPid),
    PuertaId = maps:get(id, EstadoPuerta),

    case p07_puerta:validar_local(PuertaPid, CredencialId) of
        {ok, Credencial} ->
            Persona = maps:get(persona, Credencial),

            Evento = #{
                tipo => acceso_permitido,
                puerta => PuertaId,
                tarjeta => CredencialId,
                persona => Persona
            },

            case p07_personas_dentro:registrar_entrada(
                CredencialId,
                Persona,
                Evento
            ) of
                {ok, EventoId} ->
                    case p07_puerta:abrir(PuertaPid) of
                        {ok, abierta} ->
                            {ok, acceso_permitido, EventoId};

                        {error, Razon} ->
                            {error, puerta_no_abierta, Razon}
                    end;

                {error, anti_passback} ->
                    {error, acceso_denegado, anti_passback};

                {error, Razon} ->
                    {error, error_registro_local, Razon}
            end;

        {error, Razon} ->
            {error, acceso_denegado, Razon}
    end.

%% Registrar salida
registrar_salida(CredencialId) ->
    p07_personas_dentro:registrar_salida(CredencialId).

%% Consultar personas dentro
personas_dentro() ->
    p07_personas_dentro:personas_dentro().
