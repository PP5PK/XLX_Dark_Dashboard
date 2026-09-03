<?php
session_start();
if (file_exists("./pgs/functions.php")) {
    require_once("./pgs/functions.php");
} else {
    die("functions.php does not exist.");
}
if (file_exists("./pgs/config.inc.php")) {
    require_once("./pgs/config.inc.php");
} else {
    die("config.inc.php does not exist.");
}

if (!class_exists('ParseXML'))   require_once("./pgs/class.parsexml.php");
if (!class_exists('Node'))       require_once("./pgs/class.node.php");
if (!class_exists('xReflector')) require_once("./pgs/class.reflector.php");
if (!class_exists('Station'))    require_once("./pgs/class.station.php");
if (!class_exists('Peer'))       require_once("./pgs/class.peer.php");
if (!class_exists('Interlink'))  require_once("./pgs/class.interlink.php");

$Reflector = new xReflector();
$Reflector->SetFlagFile("./pgs/country.csv");
$Reflector->SetPIDFile($Service['PIDFile']);
$Reflector->SetXMLFile($Service['XMLFile']);

$ReflectorLoaded = $Reflector->LoadXML();

if ($ReflectorLoaded === false) {
    // xlxd may be rewriting xlxd.xml at this exact moment.
    http_response_code(503);
    header('Retry-After: 1');
    exit('Reflector data is temporarily unavailable. Please retry in a moment.');
}

if ($CallingHome['Active']) {
    $CallHomeNow = false;
    $LastSync = 0;
    $Hash = "";

    if (!file_exists($CallingHome['HashFile'])) {
        $Ressource = fopen($CallingHome['HashFile'], "w+");
        if ($Ressource) {
            $Hash = CreateCode(16);
            @fwrite($Ressource, "<?php\n");
            @fwrite($Ressource, "\n".'$Hash = "'.$Hash.'";');
            @fwrite($Ressource, "\n\n".'?>');
            @fflush($Ressource);
            @fclose($Ressource);
            @chmod($CallingHome['HashFile'], 0777);
        }
    } else {
        require_once($CallingHome['HashFile']);
    }

    if (@file_exists($CallingHome['LastCallHomefile'])) {
        if (@is_readable($CallingHome['LastCallHomefile'])) {
            $tmp = @file($CallingHome['LastCallHomefile']);
            if (isset($tmp[0])) {
                $LastSync = $tmp[0];
            }
            unset($tmp);
        }
    }

    if ($LastSync < (time() - $CallingHome['PushDelay'])) {
        $CallHomeNow = true;
        $Ressource = @fopen($CallingHome['LastCallHomefile'], "w+");
        if ($Ressource) {
            @fwrite($Ressource, time());
            @fflush($Ressource);
            @fclose($Ressource);
            @chmod($CallingHome['LastCallHomefile'], 0777);
        }
    }

    if ($CallHomeNow || isset($_GET['callhome'])) {
        $Reflector->SetCallingHome($CallingHome, $Hash);
        $Reflector->ReadInterlinkFile();
        $Reflector->PrepareInterlinkXML();
        $Reflector->PrepareReflectorXML();
        $Reflector->CallHome();
    }
} else {
    $Hash = "";
}

// Checks if the request is AJAX
$isAjax = !empty($_SERVER['HTTP_X_REQUESTED_WITH']) && strtolower($_SERVER['HTTP_X_REQUESTED_WITH']) == 'xmlhttprequest';

// Sets $_GET['show'] to empty if not defined
$show = isset($_GET['show']) ? $_GET['show'] : '';

if (!$isAjax) {
    // If it is not an AJAX request, it includes the DOCTYPE, <html>, <head> and <script>
    echo '<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="description" content="' . htmlspecialchars($PageOptions['MetaDescription']) . '">
    <meta name="keywords" content="' . htmlspecialchars($PageOptions['MetaKeywords']) . '">
    <meta name="author" content="' . htmlspecialchars($PageOptions['MetaAuthor']) . '">
    <meta name="revisit" content="' . htmlspecialchars($PageOptions['MetaRevisit']) . '">
    <meta name="robots" content="' . htmlspecialchars($PageOptions['MetaAuthor']) . '">
    <meta name="viewport" content="width=device-width, initial-scale=0.38">
    <meta name="apple-mobile-web-app-title" content="XLX Reflector" />
    <title>' . htmlspecialchars($PageOptions['CustomTXT']) . '</title>
    <link rel="stylesheet" type="text/css" href="./css/layout.css">
    <link rel="icon" type="image/png" href="./img/favicon/favicon-96x96.png" sizes="96x96" />
    <link rel="icon" type="image/svg+xml" href="./img/favicon/favicon.svg" />
    <link rel="shortcut icon" href="./img/favicon/favicon.ico" />
    <link rel="apple-touch-icon" sizes="180x180" href="./img/favicon/apple-touch-icon.png" />
    <link rel="manifest" href="./img/favicon/site.webmanifest" />';

    if ($PageOptions['PageRefreshActive']) {
        echo '
        <script src="https://ajax.googleapis.com/ajax/libs/jquery/3.7.1/jquery.min.js"></script>
        <script>
            var PageRefresh;

            function updateTitle() {
                // If TX timer is running, let it control the title
                if (window.txActive) return;
                var connected = $("#menubar a[href*=\'repeaters\']").text().match(/\((\d+)\)/);
                var stations  = connected ? connected[1] : "0";
                var baseTitle = "' . addslashes($PageOptions['CustomTXT']) . '";
                if (stations > 0) {
                    document.title = "(" + stations + ") " + baseTitle;
                } else {
                    document.title = baseTitle;
                }
            }

            function ReloadPage() {
                var url = "./index.php?show=' . urlencode($show) . '";
                // Captura filtros ANTES de substituir o body
                var csFilter  = $("input[name=\'txtSetCallsignFilter\']").val() || "";
                var modFilter = $("input[name=\'txtSetModuleFilter\']").val() || "";
                var prFilter  = $("input[name=\'txtSetProtocolFilter\']").val() || "";
                $.get(url, function(data) {
                    console.log("Updating body content...");
                    // Clear TX timer interval before replacing body
                    if (window.txTimerInterval) {
                        clearInterval(window.txTimerInterval);
                        window.txTimerInterval = null;
                    }
                    $("body").html(data);
                    updateTitle();
                })
                    .fail(function(jqXHR, textStatus, errorThrown) {
                        console.error("Error in AJAX request: " + textStatus + ", " + errorThrown);
                    })
                    .always(function() {
                        if (!csFilter && !modFilter && !prFilter) {
                            PageRefresh = setTimeout(ReloadPage, ' . $PageOptions['PageRefreshDelay'] . ');
                        }
                    });
            }';

        if ($show === '' || ($show !== 'liveircddb' && $show !== 'reflectors' && $show !== 'interlinks' && $show !== 'modules')) {
            $hasFilter = !empty($_SESSION['FilterCallSign']) || !empty($_SESSION['FilterModule']) || !empty($_SESSION['FilterProtocol']);
            if (!$hasFilter) {
                echo '
            PageRefresh = setTimeout(ReloadPage, ' . $PageOptions['PageRefreshDelay'] . ');';
            }
        }
        echo '

            function SuspendPageRefresh() {
                clearTimeout(PageRefresh);
            }
        </script>';
    }

    echo '
</head>
<body>';
}

// Contents of <body> (will be returned for both normal and AJAX requests)
?>
    <?php if (file_exists("./tracking.php")) { include_once("tracking.php"); }?>
    <div id="top" style="text-align: center;">
        <img src="./img/300_header.png" alt="XLX Gateway" style="margin: 0 auto;">
    </div>
    <div id="menubar">
        <div id="menu">
            <table border="0">
                <tr>
                    <td><a href="./index.php" class="menulink<?php if ($show === '') { echo 'active'; } ?>">Recent Activity</a></td>
                    <td><a href="./index.php?show=repeaters" class="menulink<?php if ($show === 'repeaters') { echo 'active'; } ?>"
			>Connected Stations (<?php echo $Reflector->NodeCount(); ?>)</a></td>
                    <?php
                    if ($PageOptions['Peers']['Show']) {
                        echo '
                        <td><a href="./index.php?show=peers" class="menulink';
                        if ($show === 'peers') { echo 'active'; }
                        echo '">Links (' . $Reflector->PeerCount() . ')</a></td>';
                    }
                    ?>
                    <td><a href="./index.php?show=modules" class="menulink<?php if ($show === 'modules') { echo 'active'; } ?>">Active Modules</a></td>
                    <td><a href="./index.php?show=reflectors" class="menulink<?php if ($show === 'reflectors') { echo 'active'; } ?>">XLX Reflectors</a></td>
                    <?php
                    if ($PageOptions['Traffic']['Show']) {
                        echo '
                        <td><a href="./index.php?show=traffic" class="menulink';
                        if ($show === 'traffic') { echo 'active'; }
                        echo '">Network</a></td>';
                    }
                    if ($PageOptions['IRCDDB']['Show']) {
                        echo '
                        <td><a href="./index.php?show=liveircddb" class="menulink';
                        if ($show === 'liveircddb') { echo 'active'; }
                        echo '">Traffic</a></td>';
                    }
                    ?>
                </tr>
            </table>
        </div>
    </div>
    <div id="content" align="center">
        <?php
        if ($CallingHome['Active']) {
            if (!is_readable($CallingHome['HashFile']) && (!is_writeable($CallingHome['HashFile']))) {
                echo '
                <div class="error">
                    your private hash in ' . $CallingHome['HashFile'] . ' could not be created, please check your config file and the permissions for the defined folder.
                </div>';
            }
        }

        switch ($show) {
            case 'users'      : require_once("./pgs/users.php"); break;
            case 'repeaters'  : require_once("./pgs/repeaters.php"); break;
            case 'liveircddb' : require_once("./pgs/liveircddb.php"); break;
            case 'peers'      : require_once("./pgs/peers.php"); break;
            case 'modules'    : require_once("./pgs/modules.php"); break;
            case 'reflectors' : require_once("./pgs/reflectors.php"); break;
            case 'traffic'    : require_once("./pgs/traffic.php"); break;
            default           : require_once("./pgs/users.php");
        }
        ?>
        <div style="width:100%;text-align:center;margin-top:50px;color:#c3dcba;">
            <br /><a href="./log/index.php" style="text-decoration: none; color: inherit;">D-Star</a> Multiprotocol Reflector <b><?php
		echo $Reflector->GetReflectorName(); ?></b> v<?php
		echo $Reflector->GetVersion();?> - Dashboard v<?php
		echo $PageOptions['DashboardVersion']; ?> | <?php echo $PageOptions['Footnote']; ?>
            <br />Uptime: <span id="suptime"><?php echo FormatSeconds($Reflector->GetServiceUptime());?></span>
            <?php echo '<p><a href="https://github.com/PP5PK/XLX_Installer"><center><img src="./img/Magalu_cloud.svg" width="150"></center></a></p>';?>
        </div>
        </div>
<?php
if (!$isAjax) {
    echo '
</body>
</html>';
}
?>
