#!/usr/bin/env bash
#
#

# PARAMS

# Ruta a almacén de certificados en acme.sh
ACME_DIR=/root/.acme.sh
ACME_SH=/root/.acme.sh/acme.sh

# Ruta a donde se publicarán los certificados
# El control de acceso será por carpeta desde nginx
PUBLISH_DIR=/var/www/local/certs

_MASK="0117"


# PROYECTO

readonly VER=0.1.5
readonly PROJECT_NAME="certipublisher"
readonly PROJECT="Certi Publisher

    Toma el certificado generado por acme.sh, lo exporta a pfx
    y lo copia a otra carpeta para ser servido por HTTP.

    https://github.com/aurexs/certideploy"

version() {
  echo "    $PROJECT"
  echo "    v$VER"
}

showhelp() {
  version
  cat <<- EOF

    ACME_DIR=$ACME_DIR
    ACME_SH=$ACME_SH
    PUBLISH_DIR=$PUBLISH_DIR
    _MASK=$_MASK

    Uso: $PROJECT_NAME [opciones] -d domin.io
    EJ: $PROJECT_NAME -t -V -d uan.edu.mx

    opciones:
        -d    Nombre de Dominio/Certificado
        -p    Exportar certificado a formato PKCS (.pfx)
        -q    Modo silencioso
        -t    Modo pruebas, no hace nada en realidad
        -V    Modo verbose, muestra log extendido
        -h    Opciones y ayuda
EOF
}

## --------
## Funciones utiles
## --------

color_ok="\\x1b[32m"
color_red="\\x1b[31m"
color_white="\\033[0;97m"
color_yellow="\\033[0;33m"
color_reset="\\x1b[0m"

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

  if [ -t 1 ]; then
    # Don't use colors on pipes or non-recognized terminals
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




doit () {
  is_empty "$_DOMAIN" && error "Falta nombre de dominio"
  local CERT_DIR="$ACME_DIR/$_DOMAIN"
  local CERT="$ACME_DIR/$_DOMAIN/$_DOMAIN"
  local FILES_REQ="$_DOMAIN.cer ca.cer fullchain.cer" # $_DOMAIN.pfx solo si se exporta, $_DOMAIN.key se debe distribuir a mano 
        PUBLISH_DIR=$PUBLISH_DIR/$_DOMAIN

  debug "   CERT_DIR $CERT_DIR"
  debug "PUBLISH_DIR $PUBLISH_DIR"

  # Verificar certificado generado y vigente
  ! is_dir "$CERT_DIR" && error "Ruta a dominio no encontrada [$CERT_DIR]"
  checkCertificateDates "$CERT.cer"

  # Verificar archivos requeridos
  for file in $FILES_REQ; do
    debug "Verificando lectura de $CERT_DIR/$file"
    ! is_readable "$CERT_DIR/$file" && error "No se pudo leer [$CERT_DIR/$file]"
  done

  ! is_readable "$ACME_SH" && error "No se encuentra acme.sh [$ACME_SH]"

  # Exportar a pfx con contraseña kibanana${_DOMAIN}
  if $PKCSEXPORT; then
    debug "Exportando certificados a pfx"
    $ACME_SH --toPkcs -d $_DOMAIN --password "kibanana$_DOMAIN"
    _ret=$?
    [ $_ret -ne 0 ] && warn "No se pudo exportar certificado a Pkcs"
    [ $_ret == 0 ] && FILES_REQ="$FILES_REQ $_DOMAIN.pfx"
  fi

  # Verificar carpeta de escritura sea escribible
  ! is_writeable "$PUBLISH_DIR" && error "No se puede escribir en [$PUBLISH_DIR]"

  # Si existe el archivo, lo rellena >>, sino, lo crea
  # Guarda valores originales
  [ "$_MASK" != "" ] && SAVED_UMASK=$(umask)
  [ "$_MASK" != "" ] && umask $_MASK
  #SAVED_IFS=$IFS
  #IFS=$(echo -en "\n\b")
  for file in $FILES_REQ; do
    if is_file "$PUBLISH_DIR/$file" && is_writeable "$PUBLISH_DIR/$file"; then
      info "Copiando contenido a $PUBLISH_DIR/$file"
      cat "$CERT_DIR/$file" > "$PUBLISH_DIR/$file"
    else
      info "Copiando archivo a $PUBLISH_DIR/$file"
      cp "$CERT_DIR/$file" "$PUBLISH_DIR/$file"
    fi
  done
  # Restaura valores originales
  #IFS=$SAVED_IFS
  [ "$_MASK" != "" ] && umask $SAVED_UMASK

  # Notifica a un posible webhook
  # callHook

  info "Certificados exportados. Listo!"

  return 0
}


PKCSEXPORT=false
SILENTMODE=false
TESTMODE=false
LOG_LEVEL=3

_process() {
  while [ ${#} -gt 0 ]; do
    case "${1}" in
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
      --pkcs | -p)
        PKCSEXPORT=true
        ;;
      --domain | -d)
        _DOMAIN="$2"
        _validate_required $@
        shift
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

checkCertificateDates() {
  is_empty "$1" && error "Falta certificado a verificar"

  local TARGET="$1"
  local SECS=604800 # 7 días de gracia

  if openssl x509 -checkend $SECS -noout -in $TARGET; then
    info "Certificado es válido"
    return 0
  else
    warn "Certificado caducó o esta por caducar en los próximos 7 días"
  fi
}

main() {
  [ -z "$1" ] && showhelp && return

  # _detect_sudo

  _process "$@"
}

main "$@"