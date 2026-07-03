//------------------------------------------------------------------------------


forward OnYoutubeBusca(playerid, response_code, data[]);
forward OnYoutubeConverter(playerid, response_code, data[]);


//------------------------------------------------------------------------------


#define     YTMP3_API_BASE              "IP_HOST/api_youtube.php" // RENOMEI O IP_HOST PARA O IP CORRETO
#define     YTMP3_MAX_RESULTADOS        10
#define     YTMP3_MAX_ID                16
#define     YTMP3_MAX_TITULO            64
#define     YTMP3_MAX_CANAL             40
#define     YTMP3_MAX_DURACAO           12
#define     YTMP3_MAX_URL               180
#define     YTMP3_MAX_LINHA             320
#define     YTMP3_MAX_CALLBACK          32
#define     YTMP3_INTERVALO_BUSCA       6
#define     YTMP3_INTERVALO_CONVERSAO   6


//------------------------------------------------------------------------------


static PlayerQtdResultados[MAX_PLAYERS];

static enum E_PlayerResultado
{
    RESULTADO_ID[YTMP3_MAX_ID],
    RESULTADO_TITULO[YTMP3_MAX_TITULO],
    RESULTADO_CANAL[YTMP3_MAX_CANAL],
    RESULTADO_DURACAO[YTMP3_MAX_DURACAO],
    RESULTADO_URL[YTMP3_MAX_URL]
}
static PlayerResultado[MAX_PLAYERS][YTMP3_MAX_RESULTADOS][E_PlayerResultado];


//------------------------------------------------------------------------------


static AbrirPlayerMenuBusca(playerid)
{
    return Show_Dialog(playerid, D_YTMP3_BUSCA, DIALOG_STYLE_INPUT,
        "Youtube Busca",
        "Digite o nome da musica para buscar no YouTube:",
        "Buscar", "Voltar");
}

static ResetPlayerVar(playerid)
{
    DeletePVar(playerid, "YTMP3_URL_SELECIONADA");
    DeletePVar(playerid, "YTMP3_TITULO_SELECIONADO");
    DeletePVar(playerid, "YTMP3_ID_SELECIONADO");
    DeletePVar(playerid, "YTMP3_CANAL_SELECIONADO");
    DeletePVar(playerid, "YTMP3_DURACAO_SELECIONADA");
    DeletePVar(playerid, "YTMP3_CALLBACK_SUCESSO");
    DeletePVar(playerid, "YTMP3_CALLBACK_RETORNO");
    DeletePVar(playerid, "YTMP3_TOCAR_APOS_CONVERTER");
    DeletePVar(playerid, "YTMP3_ID_TOCANDO");
    DeletePVar(playerid, "YTMP3_ID_SESSAO");
}

static bool:IsSessaoValida(playerid)
    return GetPVarInt(playerid, "YTMP3_ID_SESSAO") == GetPlayerSessao(playerid);

static ExibirPlayerResultados(playerid)
{
    if (PlayerQtdResultados[playerid] <= 0)
        return AbrirPlayerMenuBusca(playerid);

    new id_tocando[YTMP3_MAX_ID];
    GetPVarString(playerid, "YTMP3_ID_TOCANDO", id_tocando, sizeof id_tocando);

    format(string_dialog, sizeof string_dialog, "Musica\tCanal\tDuracao\tStatus\n");
    for (new i = 0; i < PlayerQtdResultados[playerid]; i++)
    {
        new status_txt[32];

        if ((!isnull(id_tocando) && !strcmp(id_tocando, PlayerResultado[playerid][i][RESULTADO_ID], false)) || IsIDTocandoSomPortatil(playerid, PlayerResultado[playerid][i][RESULTADO_ID]))
            format(status_txt, sizeof status_txt, "{76CB76}Tocando");
        else if (IsIDEmPlaylistSom(playerid, PlayerResultado[playerid][i][RESULTADO_ID]))
            format(status_txt, sizeof status_txt, "{BFBD92}Na playlist");
        else
            format(status_txt, sizeof status_txt, "{C0C0C0}-");

        strcat(string_dialog, va_return("%s\t%s\t%s\t%s\n",
            PlayerResultado[playerid][i][RESULTADO_TITULO],
            PlayerResultado[playerid][i][RESULTADO_CANAL],
            PlayerResultado[playerid][i][RESULTADO_DURACAO],
            status_txt));
    }

    return Show_Dialog(playerid, D_YTMP3_RESULTADOS, DIALOG_STYLE_TABLIST_HEADERS,
        "Resultados da busca", string_dialog, "Selecionar", "Voltar");
}

static ExibirPlayerMenuAcao(playerid)
{
    new titulo_selecionado[YTMP3_MAX_TITULO];
    GetPVarString(playerid, "YTMP3_TITULO_SELECIONADO", titulo_selecionado, sizeof titulo_selecionado);

    if (GetPVarType(playerid, "YTMP3_CALLBACK_SUCESSO") == PLAYER_VARTYPE_STRING)
    {
        format(string_dialog, sizeof string_dialog, "Acao\tDescricao\n");
        strcat(string_dialog, "Converter Musica\t{C0C0C0}Transformar link em MP3\n");

        Show_Dialog(playerid, D_YTMP3_ACAO, DIALOG_STYLE_TABLIST_HEADERS,
            va_return("Musica: %s", titulo_selecionado), string_dialog, "Selecionar", "Voltar");
    }
    return 1;
}

static bool:ProximaLinha(const texto[], &pos, linha[], maxlen)
{
    new j = 0;

    if (texto[pos] == '\0')
    {
        linha[0] = '\0';
        return false;
    }

    while (texto[pos] != '\0' && texto[pos] != '\n' && j < maxlen - 1)
    {
        if (texto[pos] != '\r')
            linha[j++] = texto[pos];

        pos++;
    }

    if (texto[pos] == '\n')
        pos++;

    linha[j] = '\0';
    return true;
}

static EncodeURL(const input[], output[], maxlen)
{
    new i, j = 0;
    new c;

    while ((c = input[i]) != '\0' && j < maxlen - 4)
    {
        if (c == ' ')
        {
            output[j++] = '%';
            output[j++] = '2';
            output[j++] = '0';
        }
        else if (c == '\n')
        {
            output[j++] = '%';
            output[j++] = '0';
            output[j++] = 'A';
        }
        else
        {
            output[j++] = c;
        }
        i++;
    }
    output[j] = '\0';
}

static bool:ParseBusca(playerid, const data[], erro[], erroLen)
{
    new pos = 0;
    new linha[YTMP3_MAX_LINHA];

    PlayerQtdResultados[playerid] = 0;

    if (!ProximaLinha(data, pos, linha, sizeof linha))
    {
        format(erro, erroLen, "Resposta vazia da API.");
        return false;
    }

    if (!strcmp(linha, "OK", true))
    {
        new id[YTMP3_MAX_ID], titulo[YTMP3_MAX_TITULO], canal[YTMP3_MAX_CANAL], duracao[YTMP3_MAX_DURACAO], url[YTMP3_MAX_URL];
        new index;

        while (ProximaLinha(data, pos, linha, sizeof linha))
        {
            if (isnull(linha))
                continue;

            if (PlayerQtdResultados[playerid] >= YTMP3_MAX_RESULTADOS)
                break;

            id[0] = '\0';
            titulo[0] = '\0';
            canal[0] = '\0';
            duracao[0] = '\0';
            url[0] = '\0';

            if (sscanf(linha, "p<|>s[15]s[95]s[39]s[11]s[179]", id, titulo, canal, duracao, url))
                continue;

            index = PlayerQtdResultados[playerid];
            format(PlayerResultado[playerid][index][RESULTADO_ID], YTMP3_MAX_ID, id);
            format(PlayerResultado[playerid][index][RESULTADO_TITULO], YTMP3_MAX_TITULO, titulo);
            format(PlayerResultado[playerid][index][RESULTADO_CANAL], YTMP3_MAX_CANAL, canal);
            format(PlayerResultado[playerid][index][RESULTADO_DURACAO], YTMP3_MAX_DURACAO, duracao);
            format(PlayerResultado[playerid][index][RESULTADO_URL], YTMP3_MAX_URL, url);
            PlayerQtdResultados[playerid]++;
        }

        if (PlayerQtdResultados[playerid] <= 0)
        {
            format(erro, erroLen, "Nenhum resultado encontrado.");
            return false;
        }

        return true;
    }

    if (!sscanf(linha, "p<|>s[7]s[127]", string_dialog, erro))
        return false;

    format(erro, erroLen, "Falha ao buscar na API.");
    return false;
}

static bool:ParseConversao(const data[], arquivo[], link[], &cache)
{
    new linha[YTMP3_MAX_LINHA];
    new pos = 0;
    new status[8], cacheTxt[4];

    if (!ProximaLinha(data, pos, linha, sizeof linha))
    {
        return false;
    }

    status[0]   = 
    arquivo[0]  = 
    link[0]     = 
    cacheTxt[0] = EOS;

    if (sscanf(linha, "p<|>s[7]s[119]s[179]s[3]", status, arquivo, link, cacheTxt))
    {
        return false;
    }

    if (strcmp(status, "OK", true))
    {
        return false;
    }

    cache = strval(cacheTxt);

    if (isnull(link))
    {
        return false;
    }

    return true;
}

stock YTMP3_AbrirPlayerBusca(playerid, const callbackSucesso[] = "", const callbackRetorno[] = "")
{
    PlayerQtdResultados[playerid] = 0;
    DeletePVar(playerid, "YTMP3_URL_SELECIONADA");
    DeletePVar(playerid, "YTMP3_TITULO_SELECIONADO");
    DeletePVar(playerid, "YTMP3_ID_SELECIONADO");
    DeletePVar(playerid, "YTMP3_CANAL_SELECIONADO");
    DeletePVar(playerid, "YTMP3_DURACAO_SELECIONADA");
    SetPVarInt(playerid, "YTMP3_ID_SESSAO", GetPlayerSessao(playerid));

    if (!isnull(callbackSucesso))
        SetPVarString(playerid, "YTMP3_CALLBACK_SUCESSO", callbackSucesso);
    else
        DeletePVar(playerid, "YTMP3_CALLBACK_SUCESSO");

    if (!isnull(callbackRetorno))
        SetPVarString(playerid, "YTMP3_CALLBACK_RETORNO", callbackRetorno);
    else
        DeletePVar(playerid, "YTMP3_CALLBACK_RETORNO");

    return AbrirPlayerMenuBusca(playerid);
}


//------------------------------------------------------------------------------


Dialog:D_YTMP3_BUSCA(playerid, response, listitem, const inputtext[])
{
    if (response)
    {
        if (isnull(inputtext))
            return Reopen_Dialog(playerid, "Digite algo para buscar.");

        new termoCodificado[140];
        new url[YTMP3_MAX_URL];

        EncodeURL(inputtext, termoCodificado, sizeof termoCodificado);
        format(url, sizeof url, "%s?action=search_text&q=%s&limite=%d", YTMP3_API_BASE, termoCodificado, YTMP3_MAX_RESULTADOS);

        new intervalo_busca = GetPVarInt(playerid, "YTMP3_INTERVALO_BUSCA") - gettime();
        if (intervalo_busca > 0)
            return Reopen_Dialog(playerid, va_return("{FFFFFF}Aguarde %d segs antes de buscar novamente.", intervalo_busca));

        SetPVarInt(playerid, "YTMP3_INTERVALO_BUSCA", gettime() + YTMP3_INTERVALO_BUSCA);
        Show_Dialog(playerid, DIALOG_NULL, DIALOG_STYLE_MSGBOX, "YouTube MP3", "Buscando resultados, aguarde...", "Fechar", "");
        HTTP(playerid, HTTP_GET, url, "", "OnYoutubeBusca");
    }
    else if (GetPVarType(playerid, "YTMP3_CALLBACK_RETORNO") == PLAYER_VARTYPE_STRING)
    {
        new callback_retorno[YTMP3_MAX_CALLBACK];
        GetPVarString(playerid, "YTMP3_CALLBACK_RETORNO", callback_retorno, sizeof callback_retorno);

        if (!isnull(callback_retorno))
            CallLocalFunction(callback_retorno, "i", playerid);

        ResetPlayerVar(playerid);
    }

    return true;
}

Dialog:D_YTMP3_RESULTADOS(playerid, response, listitem, const inputtext[])
{
    if (response)
    {
        new tituloSelecionado[YTMP3_MAX_TITULO];

        if (listitem < 0 || listitem >= PlayerQtdResultados[playerid])
            return ExibirPlayerResultados(playerid);

        SetPVarString(playerid, "YTMP3_URL_SELECIONADA", PlayerResultado[playerid][listitem][RESULTADO_URL]);
        SetPVarString(playerid, "YTMP3_TITULO_SELECIONADO", PlayerResultado[playerid][listitem][RESULTADO_TITULO]);
        SetPVarString(playerid, "YTMP3_ID_SELECIONADO", PlayerResultado[playerid][listitem][RESULTADO_ID]);
        SetPVarString(playerid, "YTMP3_CANAL_SELECIONADO", PlayerResultado[playerid][listitem][RESULTADO_CANAL]);
        SetPVarString(playerid, "YTMP3_DURACAO_SELECIONADA", PlayerResultado[playerid][listitem][RESULTADO_DURACAO]);

        GetPVarString(playerid, "YTMP3_TITULO_SELECIONADO", tituloSelecionado, sizeof tituloSelecionado);

        return ExibirPlayerMenuAcao(playerid);
    }

    return AbrirPlayerMenuBusca(playerid);
}

Dialog:D_YTMP3_ACAO(playerid, response, listitem, const inputtext[])
{
    if (response)
    {
        new urlSelecionada[YTMP3_MAX_URL];

        GetPVarString(playerid, "YTMP3_URL_SELECIONADA", urlSelecionada, sizeof urlSelecionada);

        if (isnull(urlSelecionada))
            return ExibirPlayerResultados(playerid);

        if (GetPVarType(playerid, "YTMP3_CALLBACK_SUCESSO") == PLAYER_VARTYPE_STRING)
        {
            if (listitem != 0)
                return ExibirPlayerMenuAcao(playerid);

            new intervalo_conv1 = GetPVarInt(playerid, "YTMP3_INTERVALO_CONVERSAO") - gettime();
            if (intervalo_conv1 > 0)
                return Reopen_Dialog(playerid, va_return("Aguarde %d segundo(s) antes de converter novamente.", intervalo_conv1));

            new urlCodificada[YTMP3_MAX_URL * 3];
            new requestUrl[(YTMP3_MAX_URL * 3) + 80];

            SetPVarInt(playerid, "YTMP3_TOCAR_APOS_CONVERTER", 0);
            SetPVarInt(playerid, "YTMP3_INTERVALO_CONVERSAO", gettime() + YTMP3_INTERVALO_CONVERSAO);
            EncodeURL(urlSelecionada, urlCodificada, sizeof urlCodificada);
            format(requestUrl, sizeof requestUrl, "%s?action=mp3_text&url=%s", YTMP3_API_BASE, urlCodificada);

            Show_Dialog(playerid, DIALOG_NULL, DIALOG_STYLE_MSGBOX, "YouTube MP3", "Convertendo para MP3, aguarde...", "Fechar", "");
            HTTP(playerid, HTTP_GET, requestUrl, "", "OnYoutubeConverter");
            return true;
        }
    }

    return ExibirPlayerResultados(playerid);
}


//------------------------------------------------------------------------------


public OnYoutubeBusca(playerid, response_code, data[])
{
    new erro[128];

    if (!IsSessaoValida(playerid))
    {
        return true;
    }

    if (response_code != 200)
    {
        SendErroMSG(playerid, "Falha de conexao com a API de busca.");
        return AbrirPlayerMenuBusca(playerid);
    }

    if (!ParseBusca(playerid, data, erro, sizeof erro))
    {
        SendErroMSG(playerid, erro);
        return AbrirPlayerMenuBusca(playerid);
    }

    return ExibirPlayerResultados(playerid);
}

public OnYoutubeConverter(playerid, response_code, data[])
{
    new arquivo[120], link[YTMP3_MAX_URL], cache;
    new titulo_selecionado[YTMP3_MAX_TITULO];
    new duracao_selecionada[YTMP3_MAX_DURACAO];

    if (!IsSessaoValida(playerid))
    {
        return true;
    }

    if (response_code != 200)
    {
        SendErroMSG(playerid, "Falha de conexao com a API de conversao.");
        return ExibirPlayerResultados(playerid);
    }

    if (!ParseConversao(data, arquivo, link, cache))
    {
        SendErroMSG(playerid, "Falha ao converter o video para MP3.");
        return ExibirPlayerResultados(playerid);
    }

    GetPVarString(playerid, "YTMP3_TITULO_SELECIONADO", titulo_selecionado, sizeof titulo_selecionado);
    GetPVarString(playerid, "YTMP3_DURACAO_SELECIONADA", duracao_selecionada, sizeof duracao_selecionada);

    new callback_sucesso[YTMP3_MAX_CALLBACK];
    GetPVarString(playerid, "YTMP3_CALLBACK_SUCESSO", callback_sucesso, sizeof callback_sucesso);

    if (!isnull(callback_sucesso))
    {
        CallLocalFunction(callback_sucesso, "isss", playerid, link, titulo_selecionado, duracao_selecionada);
        ResetPlayerVar(playerid);
    }
    return true;
}
