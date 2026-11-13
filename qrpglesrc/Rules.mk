# Modules of the MAPEPIRE service program (see qsrvsrc/Rules.mk)

%.MODULE: private TEXT := Mapepire RPG client

MPUTIL.MODULE: private TEXT := Mapepire: buffers, CCSID, base64, errors
MPUTIL.MODULE: mputil.rpgle mpint.rpgleinc mapepire.rpgleinc

MPTRANS.MODULE: private TEXT := Mapepire: TCP and TLS transport
MPTRANS.MODULE: mptrans.rpgle mpint.rpgleinc mapepire.rpgleinc

MPWS.MODULE: private TEXT := Mapepire: WebSocket client
MPWS.MODULE: mpws.rpgle mpint.rpgleinc mapepire.rpgleinc

MPJSON.MODULE: private TEXT := Mapepire: JSON writer and parser
MPJSON.MODULE: mpjson.rpgle mpint.rpgleinc mapepire.rpgleinc

MPSQLJOB.MODULE: private TEXT := Mapepire: SQLJob
MPSQLJOB.MODULE: mpsqljob.rpgle mpobj.rpgleinc mpint.rpgleinc mapepire.rpgleinc

MPQUERY.MODULE: private TEXT := Mapepire: Query, QueryResult, Params
MPQUERY.MODULE: mpquery.rpgle mpobj.rpgleinc mpint.rpgleinc mapepire.rpgleinc
