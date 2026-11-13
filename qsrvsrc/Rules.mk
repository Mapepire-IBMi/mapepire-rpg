# The client: service program and the binding directory applications use

MAPEPIRE.SRVPGM: private TEXT := Mapepire ILE RPG client
MAPEPIRE.SRVPGM: mapepire.bnd MPUTIL.MODULE MPTRANS.MODULE MPWS.MODULE \
                 MPJSON.MODULE MPSQLJOB.MODULE MPQUERY.MODULE

MAPEPIRE.BNDDIR: mapepire.bnddir MAPEPIRE.SRVPGM
