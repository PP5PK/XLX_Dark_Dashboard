import csv
import re
import unicodedata

# Siglas que devem permanecer em MAIÚSCULAS
EXCECOES = {
    "DMR", "YSF", "C4FM", "DSTAR", "FM", "AM", "SSB", "CW",
    "P25", "NXDN", "APCO", "TETRA", "REF", "XRF", "XLX",
    "TG", "TS", "CC", "BER", "RSSI", "GPS", "APRS", "ECHO", "IRLP"
}

# Palavras de junção que devem ficar sempre em minúsculas
JUNCAO = {
    "de", "del", "von", "da", "do", "dos", "das", "e", "y", "van", "di"
}

def remover_acentos(texto):
    return ''.join(
        c for c in unicodedata.normalize('NFD', texto)
        if unicodedata.category(c) != 'Mn'
    )

def limpar_caracteres(texto):
    # Permite letras, números, espaços e ponto
    return re.sub(r'[^a-zA-Z0-9\s.]', ' ', texto)

def expandir_iniciais(texto):
    """
    Transforma sequências como C.R.A.M. ou c.r.a.m. em C. R. A. M.
    """
    def substituir(match):
        sequencia = match.group(0)
        # Extrai cada "letra." e força maiúscula + espaço
        partes = re.findall(r'[a-zA-Z]\.', sequencia)
        return ' '.join(p[0].upper() + '.' for p in partes)

    # Procura por uma ou mais ocorrências consecutivas de (letra.)
    return re.sub(r'(?:[a-zA-Z]\.)+', substituir, texto)

def normalizar_espacos(texto):
    return re.sub(r'\s+', ' ', texto.strip())

def processar_campo(texto, coluna):
    if not texto:
        return texto

    # 1. Remove acentos
    texto = remover_acentos(texto)

    # 2. Remove sinais indesejados (mantém letras, números e ponto)
    texto = limpar_caracteres(texto)

    # 3. Expande sequências de iniciais (C.R.A.M. → C. R. A. M.)
    texto = expandir_iniciais(texto)

    # 4. Normaliza espaços
    texto = normalizar_espacos(texto)

    if not texto:
        return texto

    palavras = texto.split(' ')
    resultado = []

    for i, palavra in enumerate(palavras):
        # Detecta inicial do tipo "A."
        is_inicial = len(palavra) == 2 and palavra[0].isalpha() and palavra[1] == '.'

        # Detecta letra sozinha (apenas nos campos 3 e 4)
        is_letra_sozinha = (coluna in (2, 3)) and len(palavra) == 1 and palavra.isalpha()

        palavra_upper = palavra.upper()

        # === Regras de capitalização ===

        # 1. Inicial (letra + ponto) → SEMPRE maiúscula
        if is_inicial:
            res = palavra[0].upper() + '.'

        # 2. Regra especial para "LA"
        elif palavra_upper == "LA":
            res = "La" if i == 0 else "la"

        # 3. Palavras de junção → sempre minúsculas
        elif palavra.lower() in JUNCAO:
            res = palavra.lower()

        # 4. Palavra toda em MAIÚSCULAS e não é exceção → Title Case
        elif palavra.isupper() and palavra_upper not in EXCECOES:
            res = palavra.capitalize()

        # 5. Palavra toda em minúsculas → Title Case
        elif palavra.islower():
            res = palavra.capitalize()

        # 6. Caso misto ou já formatado → mantém
        else:
            res = palavra

        # Acrescenta o ponto se for letra sozinha nos campos 3 ou 4
        if is_letra_sozinha:
            res = res.upper() + '.'

        resultado.append(res)

    return ' '.join(resultado)

# === Configuração ===
entrada = "users_base.csv"
saida = "users_base_OK.csv"

with open(entrada, newline="", encoding="utf-8") as f_in:
    leitor = csv.reader(f_in, delimiter=",")
    linhas = list(leitor)

with open(saida, "w", newline="", encoding="utf-8") as f_out:
    escritor = csv.writer(f_out, delimiter=",")

    for linha in linhas:
        nova_linha = []
        for i, campo in enumerate(linha):
            if i < 2:  # Colunas 1 e 2 → apenas limpa espaços
                nova_linha.append(campo.strip())
            else:
                nova_linha.append(processar_campo(campo, i))
        escritor.writerow(nova_linha)

print(f"Arquivo gerado com sucesso: {saida}")
