<?php
/**
 * API YouTube - Busca e Conversão para MP3 (Versão Definitiva com Cookies e Windows Fix)
 * * Endpoints:
 * ?action=search&q=TERMO         → busca vídeos
 * ?action=mp3&url=URL_YOUTUBE    → converte para MP3 e retorna link
 * ?action=status&arquivo=NOME    → verifica se arquivo já existe
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');

// ─── Configurações ───────────────────────────────────────────────────────────
define('YTDLP_PATH',   'C:/yt-dlp/yt-dlp.exe');          
define('FFMPEG_PATH',  'C:/ffmpeg/bin/ffmpeg.exe');          

// O script vai procurar pelo cookies.txt na MESMA pasta onde ele mesmo está rodando
define('COOKIES_PATH', __DIR__ . '/cookies.txt');         

define('MP3_DIR',      __DIR__ . '/mp3/'); 
define('MP3_URL_BASE', 'http://' . ($_SERVER['HTTP_HOST'] ?? 'localhost') . '/mp3/');
define('MAX_DURATION', 600);                             // Duração máxima em segundos (10 min)
// ─────────────────────────────────────────────────────────────────────────────

$action = $_GET['action'] ?? '';

switch ($action) {
    case 'search': actionSearch(); break;
    case 'search_text': actionSearchText(); break;
    case 'mp3':    actionMp3();    break;
    case 'mp3_text': actionMp3Text(); break;
    case 'status': actionStatus(); break;
    default:
        resposta(['erro' => 'Ação inválida.', 'uso' => [
            'busca'  => '?action=search&q=TERMO',
            'busca_texto' => '?action=search_text&q=TERMO',
            'mp3'    => '?action=mp3&url=URL_YOUTUBE',
            'mp3_texto' => '?action=mp3_text&url=URL_YOUTUBE',
            'status' => '?action=status&arquivo=NOME.mp3',
        ]]);
}

// ─── Busca de vídeos ─────────────────────────────────────────────────────────
function actionSearch() {
    $q = trim($_GET['q'] ?? '');
    if (empty($q)) {
        resposta(['erro' => 'Parâmetro q é obrigatório. Ex: ?action=search&q=eminem']);
        return;
    }

    $limite   = max(1, min(10, (int)($_GET['limite'] ?? 5)));
    $pesquisa = escapeshellarg('ytsearch' . $limite . ':' . $q);
    $ytdlp    = escapeshellarg(YTDLP_PATH);
    
    $cookies = '';
    if (file_exists(COOKIES_PATH)) {
        $cookies = '--cookies ' . escapeshellarg(COOKIES_PATH);
    }
    
    $cmd = "$ytdlp $cookies --flat-playlist --match-filter \"duration <= " . MAX_DURATION . "\" -J $pesquisa 2>&1";

    $saida = shell_exec($cmd);
    $dados = json_decode($saida, true);

    if (!$dados || !isset($dados['entries'])) {
        resposta(['erro' => 'Nenhum resultado ou yt-dlp não encontrado.', 'detalhes' => $saida]);
        return;
    }

    $resultados = [];
    foreach ($dados['entries'] as $entry) {
        $id = $entry['id'] ?? '';
        if (empty($id)) continue;

        $duracao = (int)($entry['duration'] ?? 0);

        $resultados[] = [
            'id'      => $id,
            'titulo'  => $entry['title']    ?? 'Sem título',
            'canal'   => $entry['uploader'] ?? 'Desconhecido',
            'duracao' => formatarDuracao($duracao),
            'thumb'   => "https://img.youtube.com/vi/{$id}/mqdefault.jpg",
            'url'     => "https://www.youtube.com/watch?v={$id}",
        ];
    }

    resposta(['resultados' => $resultados, 'total' => count($resultados)]);
}

function actionSearchText() {
    $q = trim($_GET['q'] ?? '');
    if (empty($q)) {
        respostaTexto("ERRO|Parametro q obrigatorio");
        return;
    }

    $limite   = max(1, min(5, (int)($_GET['limite'] ?? 5)));
    $pesquisa = escapeshellarg('ytsearch' . $limite . ':' . $q);
    $ytdlp    = escapeshellarg(YTDLP_PATH);
    
    $cookies = '';
    if (file_exists(COOKIES_PATH)) {
        $cookies = '--cookies ' . escapeshellarg(COOKIES_PATH);
    }
    
    $cmd = "$ytdlp $cookies --flat-playlist --match-filter \"duration <= " . MAX_DURATION . "\" -J $pesquisa 2>&1";

    $saida = shell_exec($cmd);
    $dados = json_decode($saida, true);

    if (!$dados || !isset($dados['entries'])) {
        respostaTexto("ERRO|Falha na busca");
        return;
    }

    $linhas = ["OK"];
    foreach ($dados['entries'] as $entry) {
        $id = $entry['id'] ?? '';
        if (empty($id)) continue;

        $duracao = (int)($entry['duration'] ?? 0);
        $titulo = removerAcentos(limparCampoTexto($entry['title'] ?? 'Sem titulo'));
        $canal  = removerAcentos(limparCampoTexto($entry['uploader'] ?? 'Desconhecido'));
        $dur = formatarDuracao($duracao);
        $url = "https://www.youtube.com/watch?v={$id}";

        $linhas[] = implode('|', [$id, $titulo, $canal, $dur, $url]);
    }

    if (count($linhas) === 1) {
        respostaTexto("ERRO|Nenhum resultado");
        return;
    }

    respostaTexto(implode("\n", $linhas));
}

// ─── Converter para MP3 ───────────────────────────────────────────────────────
function actionMp3() {
    $url = trim($_GET['url'] ?? '');
    $resultado = converterParaMp3($url);
    resposta($resultado);
}

function actionMp3Text() {
    $url = trim($_GET['url'] ?? '');
    $dados = converterParaMp3($url);

    if (empty($dados['sucesso'])) {
        $erro = limparCampoTexto($dados['erro'] ?? 'Falha ao converter');
        respostaTexto("ERRO|{$erro}");
        return;
    }

    $arquivo = limparCampoTexto($dados['arquivo'] ?? 'audio.mp3');
    $link = $dados['link'] ?? '';
    $cache = !empty($dados['cache']) ? '1' : '0';

    respostaTexto("OK|{$arquivo}|{$link}|{$cache}");
}

function converterParaMp3(string $url): array {
    if (empty($url)) {
        return ['erro' => 'Parametro url e obrigatorio.'];
    }

    if (!preg_match('/^https?:\/\/(www\.)?(youtube\.com\/watch\?v=|youtu\.be\/)[a-zA-Z0-9_\-]{11}/', $url)) {
        return ['erro' => 'URL invalida. Use uma URL do YouTube padrao.'];
    }

    if (!is_dir(MP3_DIR)) {
        if (!mkdir(MP3_DIR, 0755, true)) {
            return ['erro' => 'Nao foi possivel criar a pasta mp3/. Verifique as permissoes do servidor.'];
        }
    }

    if (!preg_match('/(?:v=|youtu\.be\/)([a-zA-Z0-9_\-]{11})/', $url, $m)) {
        return ['erro' => 'Nao foi possivel extrair o ID do video.'];
    }

    $videoId = $m[1];
    $nomeArq   = $videoId . '.mp3';
    $caminhoArq = MP3_DIR . $nomeArq;

    if (file_exists($caminhoArq)) {
        return [
            'sucesso'  => true,
            'arquivo'  => $nomeArq,
            'link'     => MP3_URL_BASE . rawurlencode($nomeArq),
            'cache'    => true,
        ];
    }

    $ytdlp  = escapeshellarg(YTDLP_PATH);
    $ffmpeg = escapeshellarg(FFMPEG_PATH);
    $urlEsc = escapeshellarg($url);

    // 1. Verificação e Injeção do arquivo de cookies obtido do seu navegador
    if (file_exists(COOKIES_PATH)) {
        $cookiesCmd = '--cookies ' . escapeshellarg(COOKIES_PATH);
    } else {
        $pastaEsperada = str_replace('\\', '/', __DIR__);
        return ['erro' => "BLOQUEIO DO YOUTUBE: Coloque o seu arquivo cookies.txt dentro da pasta: {$pastaEsperada}"];
    }

    // 2. Passa apenas o ID do vídeo para o template temporário do yt-dlp (Contorna bug de string do Windows)
    $saidaTemplate = escapeshellarg(MP3_DIR . $videoId);
    
    $cmd = "$ytdlp $cookiesCmd -x --audio-format mp3 --audio-quality 0 --ffmpeg-location $ffmpeg --match-filter \"duration <= " . MAX_DURATION . "\" -o $saidaTemplate $urlEsc 2>&1";
    $saida = shell_exec($cmd);

    // 3. Se o Windows salvou o arquivo com extensões duplicadas/corrompidas, o PHP corrige o nome nativamente
    if (!file_exists($caminhoArq)) {
        $arquivosNaPasta = glob(MP3_DIR . $videoId . '*');
        if (!empty($arquivosNaPasta)) {
            @rename($arquivosNaPasta[0], $caminhoArq);
        }
    }

    if (!file_exists($caminhoArq)) {
        if (strpos($saida, 'does not pass filter') !== false) {
            return ['erro' => 'O video excede o limite permitido de ' . (MAX_DURATION / 60) . ' minutos.'];
        }
        
        $logErro = str_replace(["\r", "\n", "|"], " ", trim($saida));
        return ['erro' => 'LOG DO TERMINAL: ' . (empty($logErro) ? 'Sem resposta do shell.' : $logErro)];
    }

    return [
        'sucesso' => true,
        'arquivo' => $nomeArq,
        'link'    => MP3_URL_BASE . rawurlencode($nomeArq),
        'cache'   => false,
    ];
}

// ─── Verifica se MP3 já existe ────────────────────────────────────────────────
function actionStatus() {
    $arquivo = trim($_GET['arquivo'] ?? '');
    if (empty($arquivo)) {
        resposta(['erro' => 'Parâmetro arquivo é obrigatório.']);
        return;
    }

    $arquivo = basename($arquivo);
    $caminho = MP3_DIR . $arquivo;

    if (file_exists($caminho)) {
        resposta([
            'existe' => true,
            'link'   => MP3_URL_BASE . rawurlencode($arquivo),
            'tamanho_kb' => round(filesize($caminho) / 1024),
        ]);
    } else {
        resposta(['existe' => false]);
    }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
function resposta(array $dados): void {
    echo json_encode($dados, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
    exit;
}

function respostaTexto(string $texto): void {
    header('Content-Type: text/plain; charset=utf-8');
    echo $texto;
    exit;
}

function formatarDuracao(int $segundos): string {
    if ($segundos <= 0) return 'desconhecido';
    $h = floor($segundos / 3600);
    $m = floor(($segundos % 3600) / 60);
    $s = $segundos % 60;
    return $h > 0
        ? sprintf('%d:%02d:%02d', $h, $m, $s)
        : sprintf('%d:%02d', $m, $s);
}

function limparCampoTexto(string $texto): string {
    $texto = str_replace(["\r", "\n", "|", "\t"], ' ', $texto);
    return trim($texto);
}


function sanitizarNome(string $nome): string {
    $nome = preg_replace('/[\\\\\\/\\:\\*\\?\\\"\\<\\>\\|]/', '', $nome);
    return trim($nome);
}

function removerAcentos(string $texto): string {
    $texto = iconv('UTF-8', 'ASCII//TRANSLIT//IGNORE', $texto);
    return preg_replace('/[^A-Za-z0-9 \-]/', '', $texto);
}
