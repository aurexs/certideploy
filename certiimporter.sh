#!/usr/bin/env bash
#
#

# PARAMS

# Ruta a almacén de certificados
_PUBLISH_DIR=/etc/pki/tls/certs
# _MASK="0117"



# PROYECTO

readonly VER=0.1.5
readonly PROJECT_NAME="certiimporter"
readonly PROJECT_NAME_CASE="Certi Importer"
readonly PROJECT="$PROJECT_NAME_CASE

    Busca el certificado en una URL y lo importa
    al almacén de certificados local.
    Opcionalmente reinicia el servicio web.

    https://github.com/aurexs/certideploy"

USER_AGENT="$PROJECT_NAME/$VER ($PROJECT_NAME_CASE)"

version() {
  echo "    $PROJECT"
  echo "    v$VER"
}

showhelp() {
  version
  cat <<- EOF

    PUBLISH_DIR=$_PUBLISH_DIR

    Uso: $PROJECT_NAME [opciones] -d domin.io
    $PROJECT_NAME -d domin.io -a https://uan.mx/certs -o /ssl
    $PROJECT_NAME -V -d domin.io -a https://uan.mx/certs \\
                  -u user:password --fullchain-file /etc/nginx/ssl/domin.io.pem

    opciones:
        -d    *Nombre de Dominio/Certificado (debe coincidir con certipublisher)
        -a    *Url raiz donde está la carpeta del certificado
        -u    Usuario:contraseña para Basic Auth en certipublisher
        -o    Carpeta donde publicar bundle. Ej: /etc/ssl -> /etc/ssl/domin.io/...
              Si no se especifica, se intentará copiar a $_PUBLISH_DIR/domin.io/...
              Por default se copian los siguientes archivos:
                  domin.io.cer, ca.cer y fullchain.cer
              O si se especifican las rutas individuales, solo se copiaran esos:
        --fullchain-file  El cert+intermediario será copiado a este archivo
        --cert-file       El cert del domin.io será copiado a este archivo
        --ca-file         El cert intermediario será copiado a este archivo

        -t    Modo pruebas. Solo verifica, no hace escrituras
        -q    Modo silencioso, no muestra ningun log
        -V    Modo verbose, muestra log extendido
        -h    Opciones y ayuda

EOF
}

## --------
## Funciones utiles
## --------

# color_ok="\\x1b[32m"
color_red="\\x1b[31m"
color_white="\\033[0;97m"
color_yellow="\\033[0;33m"
color_reset="\\x1b[0m"

__INTERACTIVE=false
[ -t 1 ] && __INTERACTIVE=true

__green() {
  if [ $__INTERACTIVE ]; then
    printf '\033[1;31;32m%b\033[0m' "$1"
    return
  fi
  printf -- "%b" "$1"
}

__red() {
  if [ $__INTERACTIVE ]; then
    printf '\033[1;31;40m%b\033[0m' "$1"
    return
  fi
  printf -- "%b" "$1"
}

_contains() {
  _str="$1"
  _sub="$2"
  echo "$_str" | grep "$_sub" >/dev/null 2>&1
}

_startswith() {
  _str="$1"
  _sub="$2"
  echo "$_str" | grep "^$_sub" >/dev/null 2>&1
}

_validate_required() {
  _dvalue="$2"

  if [ "$_dvalue" ]; then
    if _startswith "$_dvalue" "-"; then
      _err "'$_dvalue' no es un valor válido para ${WHITE}'$1'"
      exit 1
    fi
  else
    _err "Falta valor para : ${WHITE}$1"
    exit 1
  fi
}

_check_program()
{
    local prog=$1

    if ! which "$prog" >/dev/null
    then
        error "'$prog' no encontrado en PATH ni en config."
        return 2 # no such file or directory
    fi
}

is_empty() {
    [[ -z $1 ]]
}

is_not_empty() {
    [[ -n $1 ]]
}

is_file() {
    [[ -f "$1" ]]
}

is_dir() {
    [[ -d "$1" ]]
}

is_writeable() {
    [[ -w "$1" ]]
}

is_readable() {
    [[ -r "$1" ]]
}


_log_format() {
    printf "[%5s]" "${1}"
}

_log() {
  # globals: SILENTMODE TESTMODE LOGFILE
  local LEVEL=$1
  shift

  local DATATIME
  DATATIME="$(date +%Y-%m-%d\ %H:%M:%S.%N | cut -b -21)"

  # Escribe al logfile si no estamos en TEST y el archivo de log existe
  # if ! $TESTMODE && is_not_empty "$LOGFILE"; then
  #     echo "${DATATIME} $(_log_format "${LEVEL}")" "${@}" >> "$LOGFILE";
  # fi

  # Ahora a la pantalla y con colores

  color=""
  if [ "${LEVEL}" = "ERROR" ]; then
    color="${color_red}"
  elif [ "${LEVEL}" = "WARN" ]; then
    color="${color_yellow}"
  elif [ "${LEVEL}" = "INFO" ]; then
    color="${color_white}"
  fi

  # if [ ! -t 1 ]; then
  if [ ! $__INTERACTIVE ]; then
    color=""; color_reset=""
  fi

  ! $SILENTMODE && \
    echo -e "${DATATIME} ${color}$(_log_format "${LEVEL}")${color_reset}" "${@}"
}

error () { [ "$LOG_LEVEL" -ge 1 ] && _log "ERROR" "${@}" >&2 || true; exit 1; } # normal
warn ()  { [ "$LOG_LEVEL" -ge 2 ] && _log "WARN" "${@}" || true; }          # normal
info ()  { [ "$LOG_LEVEL" -ge 3 ] && _log "INFO" "${@}" || true; }          # normal
notice (){ [ "$LOG_LEVEL" -ge 4 ] && _log "NOTIC" "${@}" || true; }         # -vv
debug () { [ "$LOG_LEVEL" -ge 5 ] && _log "DEBUG" "${@}" || true; }         # -vvv
# v=3

strIsA_PEM() {
  _startswith "$1" "-----BEGIN"
}

getCertExpiryDate() {
    # debug "Guardando expiración de $1"
    is_empty "$1" && error "No se pudo leer $1"

    if strIsA_PEM "$1"; then
      echo "$1" | $_OPENSSL x509 -enddate -noout 2>/dev/null || \
        error "No se pudo inspeccionar certificado remoto: $1"
      # if ! echo "$1" | $_OPENSSL x509 -enddate -noout 2>/dev/null; then
      #   error "No se pudo inspeccionar certificado remoto: $1"
      # fi
    else
      ! is_file "$1" && error "No existe para inspeccionar $1"
      $_OPENSSL x509 -enddate -noout -in "$1" 2>/dev/null || \
        error "No se pudo abrir para inspeccionar $1"
      # if ! $_OPENSSL x509 -enddate -noout -in "$1" 2>/dev/null; then
      #   error "No se pudo abrir para inspeccionar $1"
      # fi
    fi
}

areDiffLocalRemote() {
  # Guarda su fecha de expiracion
  local localDate
  local remoteCert
  # local remoteDate

  localDate=$(getCertExpiryDate "$VALIDATE_LOCAL")

  # Baja el certificado a variable
  debug "curl_cmd: $curl_cmd $CERT_REMOTE"
  remoteCert=$($curl_cmd "$CERT_REMOTE") || error "$(__green "No se pudo abrir la URL $CERT_REMOTE")" #2>/dev/null)

  # Verifica contenido, sino manda error
  ! strIsA_PEM "$remoteCert" && error "No parece ser un certificado $CERT_REMOTE"

  # Saca su fecha de expiracion
  remoteDate=$(getCertExpiryDate "$remoteCert")

  # Verifica si son los mismos
  debug "Expiracion Cert  Local[$localDate]"
  debug "Expiracion Cert Remoto[$remoteDate]"
  debug "Certificado remoto es válido hasta $remoteDate"

  # TODO: Si esta expirado, alerta por slack
  #checkCertExpiryDate "$remoteDate"

  [ "$localDate" != "$remoteDate" ]
}

downloadCerts() {
  # ! $TESTMODE && ! is_writeable "$_PUBLISH_DIR" && error "No se puede escribir en $_PUBLISH_DIR"

  debug "Descargando certificados..."

  for file in $FILES_REQ; do
    info "😋 Descargando $CERTS_URL/$file"
    local filepath
    local filename
    local basepath

    [ "$file" == "$_DOMAIN.cer" ]  && filepath="$CERT_LOCAL"
    [ "$file" == "ca.cer" ]        && filepath="$CA_LOCAL"
    [ "$file" == "fullchain.cer" ] && filepath="$FULLCHAIN_LOCAL"
    basepath=$(dirname "${filepath}")
    filename=$(basename "${filepath}")

    # local cmd="$curl_cmd "$CERTS_URL/$file" > "$filepath""
    # debug "$cmd"



    if ! is_writeable "$filepath"; then       # No existe archivo, se intentara crear si la carpeta es escribible
      ! is_writeable "$basepath" && error "🤔 No se puede escribir $filename. Primero créalo con 'touch $filepath' y asignale permisos de seguridad"
    fi

    if ! $TESTMODE; then
      # backup
      is_file "$filepath" && cp -p "$filepath" "$filepath.bak"

      # download
      if ! $curl_cmd "$CERTS_URL/$file" > "$filepath"; then
        is_file "$filepath.bak" && cat "$filepath.bak" > "$filepath"
        rm -f "$filepath.bak"
        error "$(__red "🤔 No se pudo descargar $CERTS_URL/$file") a $filepath"
      fi;

      # verificar
      strIsA_PEM "$(cat "$filepath")"
      isA_PEM_File=$?
      if [ "${file##*.}" == "cer" ] && [ "$isA_PEM_File" != "0" ]; then
        debug "$(cat "$filepath")"
        if is_file "$filepath.bak"; then
          cat "$filepath.bak" > "$filepath"
          rm -f "$filepath.bak"
        else
          rm "$filepath"
        fi
        error "🤔 Archivo descargado $(__red "NO es un certificado PEM") o está corrupto: $filepath"
      fi

      # ok
      info "    $(__red "$file") -> $(__green "$(readlink -m $filepath)")"
    else
      debug "  Guardando a $filepath"
      local certStr
      if certStr=$($curl_cmd "$CERTS_URL/$file"); then
        strIsA_PEM "$certStr"
        isA_PEM_File=$?
        if [ "${file##*.}" == "cer" ] && [ "$isA_PEM_File" != "0" ]; then
          debug "$certStr"
          error " 🤔 Archivo a descargar $(__red "NO es un certificado PEM") o está corrupto: $CERTS_URL/$file"
        fi
      else
        error "🤔 $(__red "No se pudo descargar $CERTS_URL/$file")"
      fi

      info "    $(__red "$file") -> $(__green "$(readlink -m $filepath)")"
    fi
  done

  info "👍  $(__green Exportados). Llave privada se debe exportar manualmente a $_DOMAIN.key"

  # Ejecutar reload-cmd
  if [ "$_reload_cmd" ]; then
    info "💣 Ejecutando reload cmd: $_reload_cmd"
    if $TESTMODE; then
      warn "En modo testing no se ejecuta el comando reload"
    elif (
      export DOMAIN="$_DOMAIN"
      cd "$basepath" && eval "$_reload_cmd"
    ); then
      info "$(__green "Reload OK")"
    else
      warn "Reload error"
    fi
  fi
}

doit () {
  is_empty "$_DOMAIN" && error "🤔 Falta nombre de dominio"
  is_empty "$_URL" && error "🤔 Falta url para bajar certificados"

  _check_program openssl
  _check_program curl
  _OPENSSL=$(which openssl 2>/dev/null)
  _CURL=$(which curl 2>/dev/null)
  _CURL="$_CURL -L -m 15 --silent --user-agent \"$USER_AGENT\""

  CERTS_URL="$_URL/$_DOMAIN"
  CERT_REMOTE="$_URL/$_DOMAIN/$_DOMAIN.cer"
  
  FILES_REQ="$_DOMAIN.cer ca.cer fullchain.cer" # $_DOMAIN.pfx solo si se exporta, $_DOMAIN.key se debe distribuir a mano 

  ! is_empty "$FILES_REQ_PARAM" && FILES_REQ="$FILES_REQ_PARAM"
  is_empty "$_PUBLISH_DIR"      && _PUBLISH_DIR="/etc/pki/tls/certs"

  [ "$FILES_REQ" = " ca.cer" ] && error "🤔 Se debe especificar por lo menos el $_DOMAIN.cer o el fullchain.cer"

  PUBLISH_DIR="$_PUBLISH_DIR/$_DOMAIN"            # /etc/ssl/uan.mx
  CERT_LOCAL="$PUBLISH_DIR/$_DOMAIN.cer"          # /etc/ssl/uan.mx/uan.mx.cer
  CA_LOCAL="$PUBLISH_DIR/ca.cer"                  # /etc/ssl/uan.mx/ca.cer
  FULLCHAIN_LOCAL="$PUBLISH_DIR/fullchain.cer"    # /etc/ssl/uan.mx/fullchain.cer

  ! is_empty "$_f_cert"      && CERT_LOCAL=$_f_cert
  ! is_empty "$_f_ca"        && CA_LOCAL=$_f_ca
  ! is_empty "$_f_fullchain" && FULLCHAIN_LOCAL=$_f_fullchain

  curl_cmd="$_CURL"
  ! is_empty "$_PASS" && curl_cmd="$curl_cmd -u $_PASS"

  if _contains "$FILES_REQ" "$_DOMAIN.cer"; then
    VALIDATE_LOCAL="$CERT_LOCAL"
  else
    VALIDATE_LOCAL="$FULLCHAIN_LOCAL"
  fi

  debug "  CERTS_URL $CERTS_URL"
  debug "CERT_REMOTE $CERT_REMOTE"
  debug "VALID LOCAL $(__green "$VALIDATE_LOCAL")"
  debug "FILES 2COPY $(__green "$FILES_REQ")"
  ! is_empty "$_f_cert"      && debug "$(__red $_DOMAIN.cer) -> $(__green "$(readlink -m $_f_cert)")"
  ! is_empty "$_f_ca"        && debug "       $(__red ca.cer) -> $(__green "$(readlink -m $_f_ca)")"
  ! is_empty "$_f_fullchain" && debug "$(__red fullchain.cer) -> $(__green "$(readlink -m $_f_fullchain)")"

  is_empty "$FILES_REQ_PARAM" && debug "PUBLISH_DIR $PUBLISH_DIR"
  debug "       CURL $curl_cmd"


  # Verifica que exista certificado viejo, sino se importan nuevos
  if ! is_readable "$VALIDATE_LOCAL"; then
    info "No existe $VALIDATE_LOCAL, se van a intentar importar como nuevos"

    # Si no se pidieron por separado, verifica carpeta del bundle
    if is_empty "$FILES_REQ_PARAM" && ! is_writeable "$PUBLISH_DIR"; then
      ! is_writeable "$_PUBLISH_DIR" && error "🤔 No hay cert locales y No se puede escribir en $_PUBLISH_DIR"
      debug "No existe $PUBLISH_DIR, creando nuevo"
      if ! $TESTMODE; then
        mkdir -p "$PUBLISH_DIR" || error "🤔 No se pudo crear $PUBLISH_DIR"
      fi
    fi

    downloadCerts
  else
    if areDiffLocalRemote; then
      debug "Local y remoto son diferentes, copiar nuevos"

      downloadCerts
    else
      info "Local y remoto son los mismos, no hace nada. Expira $remoteDate"
    fi
  fi;

  return 0
}


SILENTMODE=false
TESTMODE=false
LOG_LEVEL=3

remoteDate=""
FILES_REQ_PARAM=""

_process() {
  while [ ${#} -gt 0 ]; do
    case "${1}" in
      --domain | -d)
        _DOMAIN="$2"
        _validate_required "$@"
        shift
        ;;
      --url | -a)
        _URL="$2"
        _validate_required "$@"
        shift
        ;;
      --userpass | -u)
        _PASS="$2"
        _validate_required "$@"
        shift
        ;;
      --output | -o)
        _PUBLISH_DIR="$2"
        _validate_required "$@"
        shift
        ;;
      --reloadcmd | -r)
        _reload_cmd="$2"
        _validate_required "$@"
        shift
        ;;
      --cert-file)
        _f_cert="$2"
        _validate_required "$@"
        # ! is_writeable $_f_cert && error "No se puede escribir --cert-file. Primero créalo con touch $_f_cert"
        FILES_REQ_PARAM="$FILES_REQ_PARAM _DOMAIN_.cer"
        shift
        ;;
      --ca-file)
        _f_ca="$2"
        _validate_required "$@"
        # ! is_writeable $_f_ca && error "No se puede abrir $_f_ca"
        FILES_REQ_PARAM="$FILES_REQ_PARAM ca.cer"
        shift
        ;;
      --fullchain-file)
        _f_fullchain="$2"
        _validate_required "$@"
        # ! is_writeable $_f_fullchain && error "No se puede abrir $_f_fullchain"
        FILES_REQ_PARAM="$FILES_REQ_PARAM fullchain.cer"
        shift
        ;;
      --quiet | -q)
        SILENTMODE=true
        ;;
      --test | -t)
        TESTMODE=true
        warn "HABILITANDO MODO TESTING. No se harán escrituras a disco"
        ;;
      --verbose | -V)
        LOG_LEVEL=5
        ;;
      --help | -h)
        showhelp
        return
        ;;
      --version | -v)
        version
        return
        ;;
      *)
        if _startswith "$1" "-"; then
          _err "Parametro desconocido : ${WHITE}$1"
          exit 1
        fi
        ;;
    esac

    shift 1
  done

  _CMD="doit"


  case "${_CMD}" in
    doit) doit ;;
    *)
      _err "Accion no válida: $_CMD"
      showhelp
      return 1
      ;;
  esac
  _ret="$?"
  if [ "$_ret" != "0" ]; then
    return $_ret
  fi
}

main() {
  [ -z "$1" ] && showhelp && return

  # _detect_sudo

  _process "$@"
}

main "$@"