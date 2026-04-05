#!/bin/bash
# =============================================================================
# Sistema unificado de gerenciamento de usuários do Refletor XLX
# Funções: base de dados (RadioID) | whitelist | acesso (htpasswd) | senhas
#
# Coringas disponíveis em campos de entrada:
#   X  → cancela a operação e volta ao menu anterior
#   -  → (somente campo DMRID) apaga o DMRID do registro
# =============================================================================

# --------------------------------------------
# CONFIGURAÇÕES — ajuste os caminhos se necessário
# --------------------------------------------
ARQUIVO="/xlxd/users_db/users_base.csv"
HTPASSWD="/var/www/restricted/.htpasswd"
PENDENTES="/var/www/restricted/pendentes.txt"
WHITELIST="/xlxd/xlxd.whitelist"
CREATE_DB_PHP="/xlxd/users_db/create_user_db.php"

ESCAPE="X"
CLEAR="-"
MAX_W=70        # largura máxima desejada em colunas

# --------------------------------------------
# CORES
# --------------------------------------------
RST=$'\e[0m'
BOLD=$'\e[1m'
DIM=$'\e[2m'
CYAN=$'\e[36m'
BCYAN=$'\e[1;36m'
BYELLOW=$'\e[1;33m'
GREEN=$'\e[32m'
BGREEN=$'\e[1;32m'
RED=$'\e[31m'
BRED=$'\e[1;31m'
MAGENTA=$'\e[35m'
WHITE=$'\e[37m'
BWHITE=$'\e[1;37m'

# --------------------------------------------
# LARGURA DINÂMICA
# Limita ao menor entre o terminal real e MAX_W.
# Recalcula ao receber SIGWINCH (redimensionamento).
# --------------------------------------------
LBL_W=10   # largura da coluna de label dentro da caixa

setup_width() {
    local cols
    cols=$(tput cols 2>/dev/null || echo 80)
    (( cols > MAX_W )) && cols=$MAX_W
    COLS=$cols

    # Comprimento da linha de separador (COLS - 2 espaços de recuo)
    local sep_len=$(( COLS - 2 ))
    SEP_LINE=$(printf '%*s' "$sep_len" '' | sed 's/ /═/g')

    # Barra horizontal da caixa (entre ┌ e ┐): COLS - 4
    local box_bar=$(( COLS - 4 ))
    BOX_BAR=$(printf '%*s' "$box_bar" '' | sed 's/ /─/g')

    # Largura do valor dentro da caixa:
    # layout: "  │ " + LBL(10) + " " + VAL + " │"
    # total  = 2 + 1 + 1 + 10 + 1 + VAL_W + 1 + 1 = VAL_W + 17 = COLS
    VAL_W=$(( COLS - LBL_W - 7 ))
    (( VAL_W < 1 )) && VAL_W=1

    # Largura interna do banner principal (entre ║ e ║): COLS - 4
    BANNER_IN=$(( COLS - 4 ))
}

trap 'setup_width' SIGWINCH
setup_width

# --------------------------------------------
# UTILITÁRIOS DE EXIBIÇÃO
# Toda saída colorida usa printf e termina com \n.
# NUNCA há código ANSI na linha onde read aguarda entrada.
# --------------------------------------------

separador() { printf "${CYAN}  %s${RST}\n" "$SEP_LINE"; }

cabecalho() {
    printf "\n"
    separador
    printf "${BCYAN}  %-*s${RST}\n" "$(( COLS - 2 ))" "$1"
    separador
}

ok()    { printf "${BGREEN}  ✔  ${GREEN}%s${RST}\n" "$*"; }
erro()  { printf "${BRED}  ✘  ${RED}%s${RST}\n"    "$*"; }
aviso() { printf "${MAGENTA}  ⚠  %s${RST}\n"        "$*"; }
info()  { printf "${CYAN}  ✔  %s${RST}\n"              "$*"; }

# Trunca string ao comprimento máximo
trunc() { printf '%s' "${1:0:$2}"; }

checar_escape() {
    if [[ "${1^^}" == "${ESCAPE^^}" ]]; then
        printf "${MAGENTA}  ↩  Operação cancelada.${RST}\n"
        return 0
    fi
    return 1
}

validar_sem_virgulas() {
    if [[ "$1" == *","* ]]; then
        erro "O campo não pode conter vírgulas."; return 1
    fi
    return 0
}

validar_usuario_acesso() {
    local U="$1"
    if [[ ! "$U" =~ ^[A-Z0-9]{4,8}$ ]] || \
       [[ $(echo "$U" | grep -o '[0-9]' | wc -l) -gt 1 ]]; then
        erro "Indicativo: 4-8 caracteres maiúsculos, máximo um dígito."
        return 1
    fi
    return 0
}

gerar_senha() {
    tr -dc 'A-Za-z0-9!@#$%^&*()-_=+' < /dev/urandom | head -c 12
}

adicionar_pendente() {
    local U="$1"
    if ! grep -q "^${U}$" "$PENDENTES" 2>/dev/null; then
        echo "$U" | sudo tee -a "$PENDENTES" > /dev/null
    fi
}

# =============================================================================
# FUNÇÕES DE LEITURA
# Padrão fixo:
#   1. printf colorido do label/hint — termina com \n
#   2. printf do marcador de entrada — SEM nenhum código ANSI
#   3. read -r da variável
# =============================================================================

# Leitura simples com label e hint opcionais
# Uso: pread VARNAME "Label" "hint"
pread() {
    local _var="$1" _label="$2" _hint="${3:-}"
    printf "${BYELLOW}  %s${RST}  ${DIM}%s${RST}\n" "$_label" "$_hint"
    printf "  > "
    read -r "$_var"
}

# Confirmação s/N
# Uso: pconfirm VARNAME "Mensagem"
pconfirm() {
    local _var="$1" _msg="$2"
    printf "${BYELLOW}  %s${RST}  ${DIM}(s/N)${RST}\n" "$_msg"
    printf "  > "
    read -r "$_var"
}

# Leitura de campo com valor pré-preenchido (Enter mantém o atual)
# Uso: ler_campo VARNAME "Label" "valor_atual" [s=obrigatorio]
# Retorna 1 se escape acionado
ler_campo() {
    local _var="$1" _label="$2" _atual="$3" _obrig="${4:-}"
    local _hint _input

    if [[ -n "$_atual" ]]; then
        _hint="[atual: ${_atual}] [${ESCAPE}=cancelar]"
    else
        _hint="[${ESCAPE}=cancelar]"
    fi

    while true; do
        printf "${BYELLOW}  %s${RST}  ${DIM}%s${RST}\n" "$_label" "$_hint"
        printf "  > "
        read -r _input
        checar_escape "$_input" && return 1
        [[ -z "$_input" && -n "$_atual" ]] && _input="$_atual"
        validar_sem_virgulas "$_input" || continue
        if [[ "$_obrig" == "s" && -z "$_input" ]]; then
            erro "Campo obrigatório."; continue
        fi
        printf -v "$_var" '%s' "$_input"
        return 0
    done
}

# --------------------------------------------
# FUNÇÕES AUXILIARES — BASE CSV
# --------------------------------------------

listar_por_callsign() {
    local CALL="$1"
    local count=0

    mapfile -t _LINHAS < <(buscar_linhas_por_call "$CALL")

    if (( ${#_LINHAS[@]} == 0 )); then
        aviso "Nenhum registro encontrado para ${CALL}."
        return
    fi

    printf "\n"
    for LN in "${_LINHAS[@]}"; do
        (( count++ ))
        printf "${BYELLOW}  %2d)${RST} %s\n" "$count" "$(sed -n "${LN}p" "$ARQUIVO")"
    done
    printf "\n"
    info "Total: ${count} registro(s) encontrado(s)."
}

buscar_linhas_por_call() {
    awk -F',' -v call="$1" '$2 == call {print NR}' "$ARQUIVO"
}

buscar_linha_por_dmrid() {
    awk -F',' -v dmr="$1" '$1 == dmr {print NR; exit}' "$ARQUIVO"
}

carregar_registro() {
    local REG
    REG=$(sed -n "${1}p" "$ARQUIVO")
    IFS=',' read -r F_DMRID F_CALL F_NOME F_SOBRENOME F_CIDADE F_ESTADO F_PAIS <<< "$REG"
}

exibir_registro() {
    setup_width   # garante medidas atualizadas
    local REG="$1"
    IFS=',' read -r _D _C _N _S _CI _E _P <<< "$REG"
    local nome_completo="$_N $_S"
    printf "${DIM}  ┌%s┐${RST}\n" "$BOX_BAR"
    printf "${DIM}  │${RST} ${CYAN}%-*s${RST} ${BWHITE}%-*s${RST} ${DIM}│${RST}\n" \
        "$LBL_W" "DMRID:"    "$VAL_W" "$(trunc "$_D"            $VAL_W)"
    printf "${DIM}  │${RST} ${CYAN}%-*s${RST} ${BWHITE}%-*s${RST} ${DIM}│${RST}\n" \
        "$LBL_W" "Indicat.:" "$VAL_W" "$(trunc "$_C"            $VAL_W)"
    printf "${DIM}  │${RST} ${CYAN}%-*s${RST} ${WHITE}%-*s${RST} ${DIM}│${RST}\n"  \
        "$LBL_W" "Nome:"     "$VAL_W" "$(trunc "$nome_completo" $VAL_W)"
    printf "${DIM}  │${RST} ${CYAN}%-*s${RST} ${WHITE}%-*s${RST} ${DIM}│${RST}\n"  \
        "$LBL_W" "Cidade:"   "$VAL_W" "$(trunc "$_CI"           $VAL_W)"
    printf "${DIM}  │${RST} ${CYAN}%-*s${RST} ${WHITE}%-*s${RST} ${DIM}│${RST}\n"  \
        "$LBL_W" "Estado:"   "$VAL_W" "$(trunc "$_E"            $VAL_W)"
    printf "${DIM}  │${RST} ${CYAN}%-*s${RST} ${WHITE}%-*s${RST} ${DIM}│${RST}\n"  \
        "$LBL_W" "Pais:"     "$VAL_W" "$(trunc "$_P"            $VAL_W)"
    printf "${DIM}  └%s┘${RST}\n" "$BOX_BAR"
}

# --------------------------------------------
# BASE CSV — CRIAR BASE SQL
# --------------------------------------------
criar_base_sql() {
    cabecalho "CRIAR / ATUALIZAR BASE DE DADOS SQL"
    printf "\n"
    info "Executando: php ${CREATE_DB_PHP}"
    printf "\n"
    if sudo php "$CREATE_DB_PHP"; then
        printf "\n"; ok "Base de dados SQL criada/atualizada com sucesso."
    else
        printf "\n"; erro "Falha ao executar o script PHP (código: $?)."
    fi
}

# --------------------------------------------
# BASE CSV — ADICIONAR / EDITAR
# --------------------------------------------
adicionar_ou_editar() {
    cabecalho "INCLUSÃO / ALTERAÇÃO DE REGISTRO"
    printf "${DIM}  Enter em campo [atual:] mantém o valor original.${RST}\n\n"

    local LINHA_EXISTENTE="" ENCONTRADO_POR=""
    local F_DMRID="" F_CALL="" F_NOME="" F_SOBRENOME="" F_CIDADE="" F_ESTADO="" F_PAIS=""
    local DMRID="" CALL="" NOME="" SOBRENOME="" CIDADE="" ESTADO="" PAIS=""

    # ── FASE 1: BUSCA POR DMRID (opcional) ──────────────────────────────────
    while true; do
        pread DMRID "DMRID (7 dígitos)" "[opcional] [${ESCAPE}=cancelar]"
        checar_escape "$DMRID" && return
        validar_sem_virgulas "$DMRID" || continue
        [[ -z "$DMRID" ]] && break

        if [[ ! "$DMRID" =~ ^[0-9]{7}$ ]]; then
            erro "DMRID inválido."; continue
        fi

        LINHA_EXISTENTE=$(buscar_linha_por_dmrid "$DMRID")
        if [[ -n "$LINHA_EXISTENTE" ]]; then
            printf "\n"; info "Registro encontrado:"
            exibir_registro "$(sed -n "${LINHA_EXISTENTE}p" "$ARQUIVO")"
            pconfirm RESP "Editar este registro?"
            [[ "$RESP" =~ ^[sS]$ ]] || return
            carregar_registro "$LINHA_EXISTENTE"
            ENCONTRADO_POR="dmrid"
        fi
        break
    done

    # ── FASE 2: BUSCA / CONFIRMAÇÃO POR INDICATIVO ──────────────────────────
    while true; do
        local _hint_call="[obrigatório] [${ESCAPE}=cancelar]"
        [[ -n "$F_CALL" ]] && _hint_call="[atual: ${F_CALL}] [${ESCAPE}=cancelar]"

        pread CALL "Indicativo (até 8 car.)" "$_hint_call"
        checar_escape "$CALL" && return
        [[ -z "$CALL" && -n "$F_CALL" ]] && CALL="$F_CALL"
        CALL=$(echo "$CALL" | tr '[:lower:]' '[:upper:]')

        validar_sem_virgulas "$CALL" || continue
        if [[ ! "$CALL" =~ ^[A-Z0-9]{1,8}$ ]]; then
            erro "Indicativo inválido."; continue
        fi

        MAPA_LINHAS=( $(buscar_linhas_por_call "$CALL") )

        if (( ${#MAPA_LINHAS[@]} > 1 )); then
            printf "\n"; info "Vários registros encontrados para ${BOLD}${CALL}${RST}:"; printf "\n"
            local IDX=1
            for LN in "${MAPA_LINHAS[@]}"; do
                printf "${BYELLOW}  %2d)${RST} %s\n" "$IDX" "$(sed -n "${LN}p" "$ARQUIVO")"
                (( IDX++ ))
            done
            printf "\n"
            local OPCAO
            while true; do
                pread OPCAO "Número do registro" "[${ESCAPE}=cancelar]"
                checar_escape "$OPCAO" && return
                if [[ "$OPCAO" =~ ^[0-9]+$ ]] && \
                   (( OPCAO >= 1 && OPCAO <= ${#MAPA_LINHAS[@]} )); then break; fi
                erro "Digite um número entre 1 e ${#MAPA_LINHAS[@]}."
            done
            local LSEL="${MAPA_LINHAS[$((OPCAO - 1))]}"
            if [[ -n "$LINHA_EXISTENTE" && "$LINHA_EXISTENTE" != "$LSEL" ]]; then
                erro "Registro selecionado diverge do DMRID informado."; return
            fi
            LINHA_EXISTENTE="$LSEL"
            carregar_registro "$LINHA_EXISTENTE"
            ENCONTRADO_POR="${ENCONTRADO_POR:-call}"
            break

        elif (( ${#MAPA_LINHAS[@]} == 1 )); then
            if [[ -n "$LINHA_EXISTENTE" && "$LINHA_EXISTENTE" != "${MAPA_LINHAS[0]}" ]]; then
                erro "Indicativo pertence a outro registro."; return
            fi
            if [[ -z "$LINHA_EXISTENTE" ]]; then
                LINHA_EXISTENTE="${MAPA_LINHAS[0]}"
                printf "\n"; info "Registro encontrado:"
                exibir_registro "$(sed -n "${LINHA_EXISTENTE}p" "$ARQUIVO")"
                pconfirm RESP "Editar este registro?"
                [[ "$RESP" =~ ^[sS]$ ]] || return
                carregar_registro "$LINHA_EXISTENTE"
                ENCONTRADO_POR="call"
            fi
            break
        fi
        break
    done

    # ── FASE 3: EDIÇÃO DOS CAMPOS ────────────────────────────────────────────
    printf "\n"; separador
    if [[ -n "$LINHA_EXISTENTE" ]]; then
        printf "${DIM}  Enter mantém o valor atual.${RST}\n"
    else
        printf "${DIM}  Novo registro. Preencha todos os campos obrigatórios.${RST}\n"
    fi
    separador; printf "\n"

    # DMRID
    local DMRID_DEFAULT="${F_DMRID:-$DMRID}"
    local _hint_dmr="[opcional] [${ESCAPE}=cancelar]"
    [[ -n "$DMRID_DEFAULT" ]] && \
        _hint_dmr="[atual: ${DMRID_DEFAULT}] [${CLEAR}=apagar] [${ESCAPE}=cancelar]"
    while true; do
        pread INPUT "DMRID (7 dígitos)" "$_hint_dmr"
        checar_escape "$INPUT" && return

        if [[ "$INPUT" == "$CLEAR" ]]; then
            pconfirm CONF "Confirmar remoção do DMRID ${DMRID_DEFAULT}?"
            if [[ "$CONF" =~ ^[sS]$ ]]; then
                DMRID=""; ok "DMRID removido."; break
            else
                aviso "Remoção cancelada."; continue
            fi
        fi

        [[ -z "$INPUT" ]] && INPUT="$DMRID_DEFAULT"
        validar_sem_virgulas "$INPUT" || continue
        if [[ -n "$INPUT" && ! "$INPUT" =~ ^[0-9]{7}$ ]]; then
            erro "DMRID inválido."; continue
        fi
        if [[ -n "$INPUT" && -z "$DMRID_DEFAULT" ]]; then
            local LINHA_CONFLITO
            LINHA_CONFLITO=$(buscar_linha_por_dmrid "$INPUT")
            if [[ -n "$LINHA_CONFLITO" ]]; then
                erro "DMRID $INPUT já está em uso:"
                exibir_registro "$(sed -n "${LINHA_CONFLITO}p" "$ARQUIVO")"
                aviso "Informe outro DMRID ou deixe em branco."; continue
            fi
        fi
        DMRID="$INPUT"; break
    done

    # Indicativo
    while true; do
        pread INPUT "Indicativo (até 8 car.)" "[atual: ${CALL}] [${ESCAPE}=cancelar]"
        checar_escape "$INPUT" && return
        [[ -z "$INPUT" ]] && INPUT="$CALL"
        INPUT=$(echo "$INPUT" | tr '[:lower:]' '[:upper:]')
        validar_sem_virgulas "$INPUT" || continue
        if [[ ! "$INPUT" =~ ^[A-Z0-9]{1,8}$ ]]; then
            erro "Indicativo inválido."; continue
        fi
        CALL="$INPUT"; break
    done

    ler_campo NOME      "Primeiro nome (obrig.)" "$F_NOME"      "s" || return
    ler_campo SOBRENOME "Sobrenome (opcional)"   "$F_SOBRENOME"     || return
    ler_campo CIDADE    "Cidade (obrig.)"        "$F_CIDADE"    "s" || return
    ler_campo ESTADO    "Estado (obrig.)"        "$F_ESTADO"    "s" || return
    ler_campo PAIS      "Pais (obrig.)"          "$F_PAIS"      "s" || return

    local NOVA="${DMRID},${CALL},${NOME},${SOBRENOME},${CIDADE},${ESTADO},${PAIS}"

    printf "\n"; separador
    info "Registro final:"
    exibir_registro "$NOVA"
    separador

    pconfirm C "Confirmar gravacao?"
    [[ "$C" =~ ^[sS]$ ]] || return

    if [[ -n "$LINHA_EXISTENTE" ]]; then
        sed -i "${LINHA_EXISTENTE}s~.*~$NOVA~" "$ARQUIVO"
        ok "Registro atualizado."
    else
        echo "$NOVA" >> "$ARQUIVO"
        ok "Registro adicionado."
    fi
}

# --------------------------------------------
# BASE CSV — EXCLUIR
# --------------------------------------------
excluir_registro() {
    cabecalho "EXCLUSAO DE REGISTRO DA BASE DE DADOS"
    printf "\n"
    printf "  ${BYELLOW}1)${RST} Excluir por DMRID\n"
    printf "  ${BYELLOW}2)${RST} Excluir por Indicativo\n"
    printf "  ${BYELLOW}X)${RST} ${DIM}Voltar${RST}\n\n"
    pread OP "Escolha" ""

    case "$OP" in
        1)
            printf "\n"
            pread DMR "DMRID (7 dígitos)" "[${ESCAPE}=cancelar]"
            checar_escape "$DMR" && return
            if [[ ! "$DMR" =~ ^[0-9]{7}$ ]]; then erro "DMRID inválido."; return; fi
            LINHA=$(buscar_linha_por_dmrid "$DMR")
            if [[ -z "$LINHA" ]]; then aviso "Nenhum registro encontrado."; return; fi
            printf "\n"
            exibir_registro "$(sed -n "${LINHA}p" "$ARQUIVO")"
            pconfirm C "Confirmar exclusao?"
            [[ "$C" =~ ^[sS]$ ]] || return
            sed -i "${LINHA}d" "$ARQUIVO"
            ok "Registro excluido."
            ;;
        2)
            printf "\n"
            pread CALL "Indicativo" "[${ESCAPE}=cancelar]"
            checar_escape "$CALL" && return
            CALL=$(echo "$CALL" | tr '[:lower:]' '[:upper:]')
            LINHAS=( $(buscar_linhas_por_call "$CALL") )

            if (( ${#LINHAS[@]} == 0 )); then aviso "Nenhum registro encontrado."; return; fi

            if (( ${#LINHAS[@]} == 1 )); then
                printf "\n"
                exibir_registro "$(sed -n "${LINHAS[0]}p" "$ARQUIVO")"
                pconfirm C "Confirmar exclusao?"
                [[ "$C" =~ ^[sS]$ ]] || return
                sed -i "${LINHAS[0]}d" "$ARQUIVO"
                ok "Registro excluido."
            else
                printf "\n"; info "Varios registros para ${BOLD}${CALL}${RST}:"; printf "\n"
                local IDX=1
                for LN in "${LINHAS[@]}"; do
                    printf "${BYELLOW}  %2d)${RST} %s\n" "$IDX" "$(sed -n "${LN}p" "$ARQUIVO")"
                    (( IDX++ ))
                done
                printf "\n"
                local OPCAO
                while true; do
                    pread OPCAO "Numero do registro" "[${ESCAPE}=cancelar]"
                    checar_escape "$OPCAO" && return
                    if [[ "$OPCAO" =~ ^[0-9]+$ ]] && \
                       (( OPCAO >= 1 && OPCAO <= ${#LINHAS[@]} )); then break; fi
                    erro "Digite um numero entre 1 e ${#LINHAS[@]}."
                done
                local LSEL="${LINHAS[$((OPCAO - 1))]}"
                printf "\n"
                exibir_registro "$(sed -n "${LSEL}p" "$ARQUIVO")"
                pconfirm C "Confirmar exclusao?"
                [[ "$C" =~ ^[sS]$ ]] || return
                sed -i "${LSEL}d" "$ARQUIVO"
                ok "Registro excluido."
            fi
            ;;
        [Xx]) return ;;
        *) erro "Opcao invalida." ;;
    esac
}

# --------------------------------------------
# ACESSO — ADICIONAR USUÁRIO
# --------------------------------------------
adicionar_usuario_acesso() {
    cabecalho "ADICIONAR USUARIO — WHITELIST E DASHBOARD"
    printf "\n"

    pread USUARIO "Indicativo do usuario" "[${ESCAPE}=cancelar]"
    checar_escape "$USUARIO" && return
    USUARIO=$(echo "$USUARIO" | tr '[:lower:]' '[:upper:]')
    validar_usuario_acesso "$USUARIO" || return

    printf "\n"
    local FEZ_ALGO=0

    # ── Whitelist ────────────────────────────────────────────────────────────
    if grep -q "^${USUARIO}$" "$WHITELIST" 2>/dev/null; then
        aviso "Whitelist: ${USUARIO} ja esta cadastrado."
    else
        pconfirm CWL "Adicionar ${USUARIO} a whitelist do refletor?"
        if [[ "$CWL" =~ ^[sS]$ ]]; then
            echo "$USUARIO" | sudo tee -a "$WHITELIST" > /dev/null
            ok "Adicionado a whitelist do refletor."
            FEZ_ALGO=1
        else
            info "Whitelist: nenhuma alteracao."
            printf "\n"
        fi
    fi

    # ── Dashboard (htpasswd) ─────────────────────────────────────────────────
    if sudo grep -q "^${USUARIO}:" "$HTPASSWD" 2>/dev/null; then
        aviso "Dashboard: ${USUARIO} ja possui acesso."
    else
        pconfirm CDASH "Adicionar ${USUARIO} ao dashboard (gera senha)?"
        if [[ "$CDASH" =~ ^[sS]$ ]]; then
            local SENHA
            SENHA=$(gerar_senha)
            sudo htpasswd -b "$HTPASSWD" "$USUARIO" "$SENHA"
            adicionar_pendente "$USUARIO"
            FEZ_ALGO=1
            printf "\n"; separador
            ok "Acesso ao dashboard criado para ${BOLD}${USUARIO}${RST}${GREEN}!"
            printf "${CYAN}  %-18s${RST}${BWHITE}%s${RST}\n" "Senha inicial:" "$SENHA"
            printf "${DIM}  OBS: alterar a senha no primeiro login.${RST}\n"
            separador
        else
            info "Dashboard: nenhuma alteracao."
        fi
    fi

    [[ $FEZ_ALGO -eq 0 ]] && aviso "Nenhuma alteracao realizada."
}

# --------------------------------------------
# ACESSO — RESETAR SENHA
# --------------------------------------------
resetar_senha() {
    cabecalho "RESETAR SENHA DO DASHBOARD"
    printf "\n"

    pread USUARIO "Indicativo do usuario" "[${ESCAPE}=cancelar]"
    checar_escape "$USUARIO" && return
    USUARIO=$(echo "$USUARIO" | tr '[:lower:]' '[:upper:]')
    validar_usuario_acesso "$USUARIO" || return

    if ! sudo grep -q "^${USUARIO}:" "$HTPASSWD" 2>/dev/null; then
        erro "Usuario nao encontrado no dashboard!"; return
    fi

    SENHA=$(gerar_senha)
    printf "\n"; info "Atualizando senha..."
    sudo sed -i "/^${USUARIO}:/d" "$HTPASSWD"
    sudo htpasswd -b "$HTPASSWD" "$USUARIO" "$SENHA"
    adicionar_pendente "$USUARIO"

    printf "\n"; separador
    ok "Senha alterada para ${BOLD}${USUARIO}${RST}${GREEN}!"
    printf "${CYAN}  %-18s${RST}${BWHITE}%s${RST}\n" "Nova senha:" "$SENHA"
    printf "${DIM}  OBS: alterar a senha no primeiro login.${RST}\n"
    separador
}

# --------------------------------------------
# ACESSO — REMOVER USUÁRIO
# --------------------------------------------
remover_usuario_acesso() {
    cabecalho "REMOVER USUARIO — WHITELIST E DASHBOARD"
    printf "\n"

    pread USUARIO "Indicativo do usuario" "[${ESCAPE}=cancelar]"
    checar_escape "$USUARIO" && return
    USUARIO=$(echo "$USUARIO" | tr '[:lower:]' '[:upper:]')
    validar_usuario_acesso "$USUARIO" || return

    local REMOVIDO=0; printf "\n"

    if sudo grep -q "^${USUARIO}:" "$HTPASSWD" 2>/dev/null; then
        pconfirm C "Remover acesso ao dashboard para ${USUARIO}?"
        if [[ "$C" =~ ^[sS]$ ]]; then
            sudo sed -i "/^${USUARIO}:/d" "$HTPASSWD"
            ok "Removido do dashboard."; REMOVIDO=1
        fi
    else
        aviso "Usuario nao encontrado no dashboard."
    fi

    if grep -q "^${USUARIO}$" "$WHITELIST" 2>/dev/null; then
        pconfirm C "Remover tambem da whitelist?"
        if [[ "$C" =~ ^[sS]$ ]]; then
            sudo sed -i "/^${USUARIO}$/d" "$WHITELIST"
            ok "Removido da whitelist do refletor."; REMOVIDO=1
        fi
    fi

    if grep -q "^${USUARIO}$" "$PENDENTES" 2>/dev/null; then
        sudo sed -i "/^${USUARIO}$/d" "$PENDENTES"
    fi

    [[ $REMOVIDO -eq 0 ]] && aviso "Nenhuma alteracao realizada."
}

# --------------------------------------------
# ACESSO — CONSULTAR USUÁRIO
# --------------------------------------------
consultar_usuario_acesso() {
    cabecalho "CONSULTAR USUARIO — WHITELIST E DASHBOARD"
    printf "\n"

    pread USUARIO "Indicativo do usuario" "[${ESCAPE}=cancelar]"
    checar_escape "$USUARIO" && return
    USUARIO=$(echo "$USUARIO" | tr '[:lower:]' '[:upper:]')
    validar_usuario_acesso "$USUARIO" || return

    printf "\n"
    separador
    printf "${BCYAN}  Status: ${BOLD}%s${RST}\n" "$USUARIO"
    separador

    # Whitelist
    if grep -q "^${USUARIO}$" "$WHITELIST" 2>/dev/null; then
        ok "Whitelist do refletor:  PRESENTE"
    else
        erro "Whitelist do refletor:  AUSENTE"
    fi

    # Dashboard
    if sudo grep -q "^${USUARIO}:" "$HTPASSWD" 2>/dev/null; then
        ok "Acesso ao dashboard:    PRESENTE"
        # Pendentes só faz sentido se o usuário tem acesso ao dashboard
        if grep -q "^${USUARIO}$" "$PENDENTES" 2>/dev/null; then
            aviso "Lista de pendentes:     PRESENTE (senha nao alterada)"
        else
            info  "Lista de pendentes:     OK (senha ja foi alterada)"
        fi
    else
        erro "Acesso ao dashboard:    AUSENTE"
    fi

    separador
}

# --------------------------------------------
# MENUS
# --------------------------------------------

# --------------------------------------------
# ACESSO — LISTAR PENDENTES
# --------------------------------------------
listar_pendentes() {
    cabecalho "USUARIOS COM SENHA PENDENTE DE ALTERACAO"
    printf "\n"

    if [[ ! -f "$PENDENTES" ]] || [[ ! -s "$PENDENTES" ]]; then
        ok "Nenhum usuario com senha pendente."
        return
    fi

    local count=0
    while IFS= read -r linha; do
        [[ -z "$linha" ]] && continue
        printf "  ${BYELLOW}•${RST} %s\n" "$linha"
        (( count++ ))
    done < "$PENDENTES"

    printf "\n"
    info "Total: ${count} usuario(s) com senha pendente de alteracao."
    separador
}

# --------------------------------------------
# ACESSO — LISTAR WHITELIST EM COLUNAS
# --------------------------------------------
listar_whitelist() {
    cabecalho "INDICATIVOS NA WHITELIST DO REFLETOR"
    printf "\n"

    if [[ ! -f "$WHITELIST" ]] || [[ ! -s "$WHITELIST" ]]; then
        aviso "Whitelist vazia ou arquivo nao encontrado."
        return
    fi

    # Carrega entradas validas: ignora linhas vazias e comentarios (#)
    mapfile -t _ENTRIES < <(grep -v '^[[:space:]]*#' "$WHITELIST" | grep -v '^[[:space:]]*$' | sort)
    local total=${#_ENTRIES[@]}

    if (( total == 0 )); then
        aviso "Nenhum indicativo encontrado na whitelist."
        return
    fi

    # Largura de cada célula: maior indicativo + 2 espaços de padding
    local max_len=0
    for e in "${_ENTRIES[@]}"; do
        (( ${#e} > max_len )) && max_len=${#e}
    done
    local cell_w=$(( max_len + 2 ))
    (( cell_w < 6 )) && cell_w=6

    # Quantas colunas cabem na área útil (COLS - 2 de recuo)
    local area=$(( COLS - 2 ))
    local ncols=$(( area / cell_w ))
    (( ncols < 1 )) && ncols=1

    # Impressão em colunas
    local col=0
    printf "  "
    for e in "${_ENTRIES[@]}"; do
        printf "${BWHITE}%-*s${RST}" "$cell_w" "$e"
        (( col++ ))
        if (( col >= ncols )); then
            printf "\n  "
            col=0
        fi
    done
    # Fecha a última linha se não terminou na borda
    (( col > 0 )) && printf "\n"

    printf "\n"
    info "Total: ${total} indicativo(s) na whitelist."
    separador
}

# --------------------------------------------
# BASE CSV — CONSULTA COM FILTRO E PAGINAÇÃO
# --------------------------------------------
consultar_base_csv() {
    cabecalho "CONSULTA NA BASE DE DADOS (RadioID)"
    printf "\n"

    # ── Escolha do campo ─────────────────────────────────────────────────────
    printf "  Filtrar por:\n\n"
    printf "  ${BYELLOW}1)${RST} Indicativo  "
    printf "${BYELLOW}2)${RST} DMRID  "
    printf "${BYELLOW}3)${RST} Nome  "
    printf "${BYELLOW}4)${RST} Cidade  "
    printf "${BYELLOW}5)${RST} Pais\n\n"
    pread CAMPO "Campo" "[${ESCAPE}=cancelar]"
    checar_escape "$CAMPO" && return

    local awk_col label
    case "$CAMPO" in
        1) awk_col=2; label="Indicativo" ;;
        2) awk_col=1; label="DMRID"      ;;
        3) awk_col=0; label="Nome"       ;;   # 0 = busca em col 3 e 4
        4) awk_col=5; label="Cidade"     ;;
        5) awk_col=7; label="Pais"       ;;
        *) erro "Opcao invalida."; return ;;
    esac

    # ── Termo de busca ───────────────────────────────────────────────────────
    printf "\n"
    pread TERMO "Termo de busca (parcial)" "[${ESCAPE}=cancelar]"
    checar_escape "$TERMO" && return
    [[ -z "$TERMO" ]] && { erro "Termo nao pode ser vazio."; return; }

    # ── Converter glob * em regex .* para comportamento intuitivo ───────────
    local TERMO_RE="${TERMO//\*/.*}"

    # ── Busca via awk — resultado em arquivo temporário ──────────────────────
    local TMPFILE
    TMPFILE=$(mktemp /tmp/xlxd_query.XXXXXX)

    info "Buscando..."
    if [[ "$CAMPO" == "3" ]]; then
        awk -F',' -v t="${TERMO_RE,,}" \
            'NR>1 && (tolower($3) ~ t || tolower($4) ~ t)' \
            "$ARQUIVO" > "$TMPFILE"
    else
        awk -F',' -v col="$awk_col" -v t="${TERMO_RE,,}" \
            'NR>1 && tolower($col) ~ t' \
            "$ARQUIVO" > "$TMPFILE"
    fi

    local total
    total=$(wc -l < "$TMPFILE")

    if (( total == 0 )); then
        rm -f "$TMPFILE"
        aviso "Nenhum registro encontrado para \"${TERMO}\" em ${label}."
        return
    fi

    # ── Larguras de coluna para tabela compacta ──────────────────────────────
    # layout (indent 2): DMRID(8) CALL(9) NOME(18) CIDADE(14) PAIS(resto)
    local W_DMR=8 W_CALL=9 W_NAME=18 W_CITY=14
    local W_CTRY=$(( COLS - 2 - W_DMR - W_CALL - W_NAME - W_CITY ))
    (( W_CTRY < 6 )) && W_CTRY=6

    # ── Paginação ────────────────────────────────────────────────────────────
    local PAGE_SIZE=25
    local page=1
    local total_pages=$(( (total + PAGE_SIZE - 1) / PAGE_SIZE ))
    local nav

    while true; do
        local start=$(( (page - 1) * PAGE_SIZE + 1 ))
        local end=$(( page * PAGE_SIZE ))
        (( end > total )) && end=$total

        printf "\n"

        # Cabeçalho da tabela
        printf "${CYAN}  %-*s%-*s%-*s%-*s%-*s${RST}\n" \
            $W_DMR  "DMRID" \
            $W_CALL "INDICAT." \
            $W_NAME "NOME" \
            $W_CITY "CIDADE" \
            $W_CTRY "PAIS"
        separador

        # Linhas da página (sed faz o slice eficiente no tmpfile)
        while IFS=',' read -r _D _C _N _S _CI _E _P; do
            _P="${_P%$'\r'}"   # remove \r de line endings Windows
            local nome_full="${_N} ${_S}"
            printf "  ${DIM}%-*s${RST}${BYELLOW}%-*s${RST}${WHITE}%-*s${RST}${DIM}%-*s%-*s${RST}\n" \
                $W_DMR  "$(trunc "$_D"        $(( W_DMR  - 1 )))" \
                $W_CALL "$(trunc "$_C"        $(( W_CALL - 1 )))" \
                $W_NAME "$(trunc "$nome_full" $(( W_NAME - 1 )))" \
                $W_CITY "$(trunc "$_CI"       $(( W_CITY - 1 )))" \
                $W_CTRY "$(trunc "$_P"        $(( W_CTRY - 1 )))"
        done < <(sed -n "${start},${end}p" "$TMPFILE")

        separador
        printf "${DIM}  Pagina %d/%d — %d registro(s) | filtro: \"%s\" em %s${RST}\n" \
            "$page" "$total_pages" "$total" "$TERMO" "$label"

        # Controles de navegação
        if (( total_pages == 1 )); then
            printf "\n"; break
        fi

        printf "\n"
        local hint_nav=""
        (( page < total_pages )) && hint_nav="${BYELLOW}[Enter]${RST}${DIM} proxima${RST}  "
        (( page > 1 ))           && hint_nav+="${BYELLOW}[P]${RST}${DIM} anterior${RST}  "
        hint_nav+="${BYELLOW}[${ESCAPE}]${RST}${DIM} sair${RST}"
        printf "  %b\n" "$hint_nav"
        printf "  > "
        read -r nav

        case "${nav^^}" in
            "$ESCAPE") break ;;
            P) (( page > 1 )) && (( page-- )) ;;
            *)
                if (( page < total_pages )); then
                    (( page++ ))
                else
                    break   # última página: Enter sai
                fi
                ;;
        esac
    done

    rm -f "$TMPFILE"
}

menu_base_dados() {
    while true; do
        cabecalho "BASE DE DADOS (RadioID)"
        printf "  ${BYELLOW}1)${RST} Adicionar / Alterar registro\n"
        printf "  ${BYELLOW}2)${RST} Excluir registro\n"
        printf "  ${BYELLOW}3)${RST} Listar registros por Indicativo\n"
        printf "  ${BYELLOW}4)${RST} Consultar registros ${DIM}(filtro)${RST}\n"
        printf "  ${BYELLOW}5)${RST} Criar / Atualizar base de dados SQL\n"
        printf "  ${BYELLOW}X)${RST} ${DIM}Voltar ao menu principal${RST}\n"
        separador
        pread OP "Escolha" ""

        case "$OP" in
            1) adicionar_ou_editar ;;
            2) excluir_registro ;;
            3)
                printf "\n"
                pread CALL "Indicativo" "[${ESCAPE}=cancelar]"
                checar_escape "$CALL" && continue
                CALL=$(echo "$CALL" | tr '[:lower:]' '[:upper:]')
                printf "\n"; listar_por_callsign "$CALL"
                ;;
            4) consultar_base_csv ;;
            5) criar_base_sql ;;
            [Xx]) return ;;
            *) erro "Opcao invalida." ;;
        esac
    done
}

menu_acesso() {
    while true; do
        cabecalho "CONTROLE DE ACESSO"
        printf "  ${BYELLOW}1)${RST} Adicionar usuario   ${DIM}(whitelist + dashboard)${RST}\n"
        printf "  ${BYELLOW}2)${RST} Resetar senha       ${DIM}(dashboard)${RST}\n"
        printf "  ${BYELLOW}3)${RST} Remover usuario     ${DIM}(whitelist + dashboard)${RST}\n"
        printf "  ${BYELLOW}4)${RST} Consultar usuario   ${DIM}(whitelist + dashboard)${RST}\n"
        printf "  ${BYELLOW}5)${RST} Listar pendentes    ${DIM}(senha nao alterada)${RST}\n"
        printf "  ${BYELLOW}6)${RST} Listar whitelist    ${DIM}(todos os indicativos)${RST}\n"
        printf "  ${BYELLOW}X)${RST} ${DIM}Voltar ao menu principal${RST}\n"
        separador
        pread OP "Escolha" ""

        case "$OP" in
            1) adicionar_usuario_acesso ;;
            2) resetar_senha ;;
            3) remover_usuario_acesso ;;
            4) consultar_usuario_acesso ;;
            5) listar_pendentes ;;
            6) listar_whitelist ;;
            [Xx]) return ;;
            *) erro "Opcao invalida." ;;
        esac
    done
}

menu_principal() {
    while true; do
        setup_width
        clear
        local titulo="GERENCIAMENTO DE USUARIOS XLX"
        local tlen=${#titulo}
        local bar; bar=$(printf '%*s' "$BANNER_IN" '' | sed 's/ /═/g')
        local lpad=$(( (BANNER_IN - tlen) / 2 ))
        local rpad=$(( BANNER_IN - tlen - lpad ))
        (( lpad < 0 )) && lpad=0
        (( rpad < 0 )) && rpad=0
        local lstr; lstr=$(printf '%*s' "$lpad" '')
        local rstr; rstr=$(printf '%*s' "$rpad" '')
        printf "\n"
        printf "${BCYAN}  ╔%s╗${RST}\n" "$bar"
        printf "${BCYAN}  ║${RST}%s${BOLD}%s${RST}%s${BCYAN}║${RST}\n" "$lstr" "$titulo" "$rstr"
        printf "${BCYAN}  ╚%s╝${RST}\n" "$bar"
        printf "\n"
        printf "  ${BYELLOW}1)${RST} Base de dados ${DIM}(RadioID)${RST}\n"
        printf "  ${BYELLOW}2)${RST} Controle de acesso\n"
        printf "  ${BYELLOW}X)${RST} ${DIM}Sair${RST}\n\n"
        separador
        pread OP "Escolha" ""

        case "$OP" in
            1) menu_base_dados ;;
            2) menu_acesso ;;
            [Xx]) printf "\n${DIM}  Saindo...${RST}\n\n"; exit 0 ;;
            *) erro "Opcao invalida." ;;
        esac
    done
}

# --------------------------------------------
# PONTO DE ENTRADA
# --------------------------------------------
menu_principal
