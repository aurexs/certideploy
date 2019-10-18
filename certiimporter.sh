#!/usr/bin/env bash
#
#

# PARAMS

# Ruta a almacén de certificados en acme.sh
_PUBLISH_DIR=/etc/nginx/ssl
# _MASK="0117"



# PROYECTO

readonly VER=0.1.5
readonly PROJECT_NAME="certiimporter"
readonly PROJECT_NAME_CASE="Certi Importer"
readonly PROJECT="$PROJECT_NAME_CASE

    Busca el certificado en una URL y lo importa
    al almacén de certificados.
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
    EJ: $PROJECT_NAME -V -d uan.edu.mx -a https://uan.mx/certs -u uan:contras -o /ssl

    opciones:
        -d    Nombre de Dominio/Certificado
        -a    Url raiz donde está la carpeta del certificado
        -o    Carpeta donde publicar los certificados /ssl -> /ssl/uan.mx/uan.mx.cer
        -u    Usuario:contraseña para Basic Auth
        -t    Solo verifica, no hace escrituras
        -q    Modo silencioso
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

  localDate=$(getCertExpiryDate "$CERT_LOCAL")

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
  ! $TESTMODE && ! is_writeable "$_PUBLISH_DIR" && error "No se puede escribir en $_PUBLISH_DIR"

  debug "Descargando certificados..."

  for file in $FILES_REQ; do
    info "Descargando $CERTS_URL/$file"
    local filename
    local filepath
    filename="$file"
    filepath="$PUBLISH_DIR/$file"

    # [ "$file" == "$_DOMAIN.cer" ] && ! is_empty "$_f_cert" && filename="$_f_cert"
    # [ "$file" == "ca.cer" ] && ! is_empty "$_f_ca" && filename="$_f_ca"

    if [ "$file" == "fullchain.cer" ] && ! is_empty "$_f_fullchain"; then
      filepath_copy="$_f_fullchain"
      # filename=${_f_fullchain##*/}
    fi

    # local cmd="$curl_cmd "$CERTS_URL/$file" > "$filepath""
    # debug "$cmd"

    if ! $TESTMODE; then
      # backup
      is_file "$filepath" && cp -p "$filepath" "$filepath.bak"

      # download
      if ! $curl_cmd "$CERTS_URL/$file" > "$filepath"; then
        is_file "$filepath.bak" && cat "$filepath.bak" > "$filepath"
        error "$(__red "No se pudo descargar $CERTS_URL/$file") a $filepath"
      else
        ! is_empty "$filepath_copy" && cat $filepath > $filepath_copy
      fi;

      # verificar
      strIsA_PEM "$(cat "$filepath")"
      isA_PEM_File=$?
      if [ "$file" == "$_DOMAIN.cer" ] && [ "$isA_PEM_File" != "0" ]; then
        debug "$(cat "$filepath")"
        if is_file "$filepath.bak"; then
          cat "$filepath.bak" > "$filepath"
        else
          rm "$filepath"
        fi
        error "Archivo descargado $(__red "NO es un certificado"): $filepath"
      fi
    else
      debug "  Guardando a $filepath"
      local certStr
      if certStr=$($curl_cmd "$CERTS_URL/$file"); then
        strIsA_PEM "$certStr"
        isA_PEM_File=$?
        if [ "$file" == "$_DOMAIN.cer" ] && [ "$isA_PEM_File" != "0" ]; then
          debug "$certStr"
          error "Archivo descargado $(__red "NO es un certificado"): $CERTS_URL/$file"
        fi
      else
        error "$(__red "No se pudo descargar $CERTS_URL/$file")"
      fi
    fi
  done

  info "$(__green "Certificados exportados a $PUBLISH_DIR")"
  info "Llave privada se debe exportar manualmente a $PUBLISH_DIR/$_DOMAIN.key"

  # Ejecutar reload-cmd
  if [ "$_reload_cmd" ]; then
    info "Ejecutando reload cmd: $_reload_cmd"
    if $TESTMODE; then
      warn "En modo testing no se ejecuta el comando reload"
    elif (
      export DOMAIN="$_DOMAIN"
      cd "$PUBLISH_DIR" && eval "$_reload_cmd"
    ); then
      info "$(__green "Reload OK")"
    else
      warn "Reload error"
    fi
  fi
}

doit () {
  is_empty "$_DOMAIN" && error "Falta nombre de dominio"
  is_empty "$_URL" && error "Falta url para bajar certificados"

  _check_program openssl
  _check_program curl
  _OPENSSL=$(which openssl 2>/dev/null)
  _CURL=$(which curl 2>/dev/null)
  _CURL="$_CURL -L -m 15 --silent --user-agent \"$USER_AGENT\""


  FILES_REQ="$_DOMAIN.cer ca.cer fullchain.cer" # $_DOMAIN.pfx solo si se exporta, $_DOMAIN.key se debe distribuir a mano 
  CERTS_URL="$_URL/$_DOMAIN"
  CERT_REMOTE="$_URL/$_DOMAIN/$_DOMAIN.cer"

  PUBLISH_DIR="$_PUBLISH_DIR/$_DOMAIN"            # /etc/ssl/uan.mx
  CERT_LOCAL="$PUBLISH_DIR/$_DOMAIN.cer"          # /etc/ssl/uan.mx/uan.mx.cer
  CA_LOCAL="$PUBLISH_DIR/ca.cer"                  # /etc/ssl/uan.mx/ca.cer
  FULLCHAIN_LOCAL="$PUBLISH_DIR/fullchain.cer"    # /etc/ssl/uan.mx/fullchain.cer

  ! is_empty "$_f_cert"      && CERT_LOCAL=$_f_cert
  ! is_empty "$_f_ca"        && CA_LOCAL=$_f_ca
  ! is_empty "$_f_fullchain" && FULLCHAIN_LOCAL=$_f_fullchain

  curl_cmd="$_CURL"
  ! is_empty "$_PASS" && curl_cmd="$curl_cmd -u $_PASS"


  debug "  CERTS_URL $CERTS_URL"
  debug "CERT_REMOTE $CERT_REMOTE"
  debug "PUBLISH_DIR $PUBLISH_DIR"
  debug " CERT_LOCAL $CERT_LOCAL"
  debug "       CURL $curl_cmd"


  # Verifica que exista certificado viejo, sino se importan nuevos
  if ! is_readable "$CERT_LOCAL"; then
    info "No existe $CERT_LOCAL, se van a intentar importar como nuevos"
    if ! is_writeable "$PUBLISH_DIR"; then
      ! is_writeable "$_PUBLISH_DIR" && error "No hay cert locales y No se puede escribir en $_PUBLISH_DIR"
      debug "No existe $PUBLISH_DIR, creando nuevo"
      if ! $TESTMODE; then
        mkdir -p "$PUBLISH_DIR" || error "No se pudo crear $PUBLISH_DIR"
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
FILES_REQ="_DOMAIN_.cer"

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
        ! is_writeable $_f_cert && error "No se puede abrir $_f_cert"
        # FILES_REQ="_DOMAIN_.cer $FILES_REQ"
        shift
        ;;
      --ca-file)
        _f_ca="$2"
        _validate_required "$@"
        ! is_writeable $_f_ca && error "No se puede abrir $_f_ca"
        FILES_REQ="$FILES_REQ ca.cer"
        shift
        ;;
      --fullchain-file)
        _f_fullchain="$2"
        _validate_required "$@"
        ! is_writeable $_f_fullchain && error "No se puede abrir $_f_fullchain"
        FILES_REQ="$FILES_REQ fullchain.cer"
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