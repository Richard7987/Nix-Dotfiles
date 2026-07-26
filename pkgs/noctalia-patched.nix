{ inputs, pkgs }:

# Cherry-pick de noctalia-dev/noctalia#3629 ("fix(calendar): retain CalDAV
# password during discovery"), todavía no mergeada en upstream (HEAD:
# 96a35df5e44e4225141a9d9932d59ba28fbb7bc6, rama fix/caldav-password-ownership
# de floydya/noctalia) al momento de escribir esto.
#
# Bug real: en fetchCalDav (src/calendar/calendar_service.cpp),
# discoverCalDavCollections() recibe `password` como argumento posicional Y
# como `password = std::move(password)` en el capture-list del lambda que
# se pasa como argumento siguiente -- el orden de evaluación de argumentos
# de función en C++ no está garantizado, así que el move del capture puede
# ejecutarse antes de que se copie el argumento posicional, dejando
# discoverCalDavCollections() con un password ya vaciado. Efecto observado:
# el log tira "[calendar-caldav-discovery] missing server_url/username/password"
# pese a que la cuenta CalDAV tiene server_url/username/password válidos y
# el keyring los devuelve bien -- el calendario nunca sincroniza.
inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./noctalia-caldav-password-fix.patch ];
})
