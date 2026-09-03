<?php

if (!isset($_SESSION['FilterCallSign'])) {
    $_SESSION['FilterCallSign'] = null;
}

if (!isset($_SESSION['FilterProtocol'])) {
    $_SESSION['FilterProtocol'] = null;
}

if (!isset($_SESSION['FilterModule'])) {
    $_SESSION['FilterModule'] = null;
}

if (isset($_POST['do'])) {
    if ($_POST['do'] == 'SetFilter') {
        if (isset($_POST['txtSetCallsignFilter'])) {
            $_POST['txtSetCallsignFilter'] = trim($_POST['txtSetCallsignFilter']);
            if ($_POST['txtSetCallsignFilter'] == "") {
                $_SESSION['FilterCallSign'] = null;
            } else {
                $_SESSION['FilterCallSign'] = $_POST['txtSetCallsignFilter'];
                if (strpos($_SESSION['FilterCallSign'], "*") === false) {
                    $_SESSION['FilterCallSign'] = "*".$_SESSION['FilterCallSign']."*";
                }
            }
        }

        if (isset($_POST['txtSetProtocolFilter'])) {
            $_POST['txtSetProtocolFilter'] = trim($_POST['txtSetProtocolFilter']);
            if ($_POST['txtSetProtocolFilter'] == "") {
                $_SESSION['FilterProtocol'] = null;
            } else {
                $_SESSION['FilterProtocol'] = $_POST['txtSetProtocolFilter'];
            }
        }

        if (isset($_POST['txtSetModuleFilter'])) {
            $_POST['txtSetModuleFilter'] = trim($_POST['txtSetModuleFilter']);
            if ($_POST['txtSetModuleFilter'] == "") {
                $_SESSION['FilterModule'] = null;
            } else {
                $_SESSION['FilterModule'] = $_POST['txtSetModuleFilter'];
            }
        }
    }
}

if (isset($_GET['do'])) {
    if ($_GET['do'] == "resetfilter") {
        $_SESSION['FilterModule'] = null;
        $_SESSION['FilterProtocol'] = null;
        $_SESSION['FilterCallSign'] = null;
    }
}

// Função para obter dados do usuário do banco SQLite
function getUserData($callsign) {
    static $db = null;
    static $cache = [];

    $callsign = strtoupper(preg_replace('/\/.*/', '', $callsign));

    if (isset($cache[$callsign])) return $cache[$callsign];

    if ($db === null) {
        try { $db = new SQLite3('/xlxd/users_db/users.db', SQLITE3_OPEN_READONLY); }
        catch (Exception $e) { return $cache[$callsign] = ['name' => '-', 'city_state' => '-']; }
    }

    $stmt = $db->prepare('SELECT name, city_state FROM users WHERE callsign = :callsign LIMIT 1');
    if ($stmt === false) return $cache[$callsign] = ['name' => '-', 'city_state' => '-'];
    $stmt->bindValue(':callsign', $callsign, SQLITE3_TEXT);
    $result = $stmt->execute();

    if ($result && ($row = $result->fetchArray(SQLITE3_ASSOC))) {
        $data = [
            'name' => htmlspecialchars($row['name'], ENT_QUOTES, 'UTF-8'),
            'city_state' => htmlspecialchars($row['city_state'], ENT_QUOTES, 'UTF-8')
        ];
    } else {
        $data = ['name' => '-', 'city_state' => '-'];
    }
    $stmt->close();
    return $cache[$callsign] = $data;
}

?>

<table class="listingtable"><?php

if ($PageOptions['UserPage']['ShowFilter']) {
    echo '
    <tr>
        <th colspan="9">
            <table width="100%" border="0">
                <tr>
                    <td align="left">
                        <form name="frmFilterCallSign" method="post" action="./index.php?show=repeaters">
                            <input type="hidden" name="do" value="SetFilter" />
                            <input type="text" class="FilterField" value="'.$_SESSION['FilterCallSign'].'" name="txtSetCallsignFilter" placeholder="Callsign" onfocus="SuspendPageRefresh();" onblur="setTimeout(ReloadPage, '.$PageOptions['PageRefreshDelay'].');" />
                            <input type="submit" value="Apply" class="FilterSubmit" />
                        </form>
                    </td>';
    if (($_SESSION['FilterModule'] != null) || ($_SESSION['FilterCallSign'] != null) || ($_SESSION['FilterProtocol'] != null)) {
        echo '
                    <td><a href="./index.php?show=repeaters&do=resetfilter" class="smalllink">Disable Filters</a></td>';
    }
    echo '
                    <td align="right" style="padding-right:3px;">
                        <form name="frmFilterProtocol" method="post" action="./index.php?show=repeaters">
                            <input type="hidden" name="do" value="SetFilter" />
                            <input type="text" class="FilterField" value="'.$_SESSION['FilterProtocol'].'" name="txtSetProtocolFilter" placeholder="Protocol" onfocus="SuspendPageRefresh();" onblur="setTimeout(ReloadPage, '.$PageOptions['PageRefreshDelay'].');" />
                            <input type="submit" value="Apply" class="FilterSubmit" />
                        </form>
                    </td>
                    <td align="right" style="padding-right:3px;">
                        <form name="frmFilterModule" method="post" action="./index.php?show=repeaters">
                            <input type="hidden" name="do" value="SetFilter" />
                            <input type="text" class="FilterField" value="'.$_SESSION['FilterModule'].'" name="txtSetModuleFilter" placeholder="Module" onfocus="SuspendPageRefresh();" onblur="setTimeout(ReloadPage, '.$PageOptions['PageRefreshDelay'].');" />
                            <input type="submit" value="Apply" class="FilterSubmit" />
                        </form>
                    </td>
                </tr>
            </table>
        </th>
    </tr>';
}

?>
    <tr>
        <th width="30">#</th>
        <th width="40">Ctry</th>
        <th width="110">Gateway</th>
        <th width="220">Operator</th>
        <th width="180">Last Activity</th>
        <th width="120">Duration</th>
        <th width="100">Protocol</th>
        <th width="60">Module</th>
        <?php

if ($PageOptions['RepeatersPage']['IPModus'] != 'HideIP') {
    echo '
        <th width="140">Station IP</th>';
}

?>
    </tr>
<?php

$odd = "";
$Reflector->LoadFlags();

for ($i=0;$i<$Reflector->NodeCount();$i++) {
    $ShowThisStation = true;
    if ($PageOptions['UserPage']['ShowFilter']) {
        $CS = true;
        if ($_SESSION['FilterCallSign'] != null) {
            if (!fnmatch($_SESSION['FilterCallSign'], $Reflector->Nodes[$i]->GetCallSign(), FNM_CASEFOLD)) {
                $CS = false;
            }
        }
        $MO = true;
        if ($_SESSION['FilterModule'] != null) {
            if (trim(strtolower($_SESSION['FilterModule'])) != strtolower($Reflector->Nodes[$i]->GetLinkedModule())) {
                $MO = false;
            }
        }
        $PR = true;
        if ($_SESSION['FilterProtocol'] != null) {
            if (trim(strtolower($_SESSION['FilterProtocol'])) != strtolower($Reflector->Nodes[$i]->GetProtocol())) {
                $PR = false;
            }
        }

        $ShowThisStation = ($CS && $MO && $PR);
    }

    if ($ShowThisStation) {
        if ($odd == "#252525") { $odd = "#2c2c2c"; } else { $odd = "#252525"; }

        echo '
        <tr height="30" bgcolor="'.$odd.'" onMouseOver="this.bgColor=\'#586553\';" onMouseOut="this.bgColor=\''.$odd.'\';">
            <td align="center">'.($i+1).'</td>
            <td align="center">';
        list ($Flag, $Name) = $Reflector->GetFlag($Reflector->Nodes[$i]->GetCallSign());
        if (file_exists("./img/flags/".$Flag.".png")) {
            echo '<a href="#" class="tip"><img src="./img/flags/'.$Flag.'.png" height="15" alt="'.$Name.'" /><span>'.$Name.'</span></a>';
        }
        echo '</td>
            <td align="center">';
        $FullCallsign = $Reflector->Nodes[$i]->GetCallSign();
        $Suffix = $Reflector->Nodes[$i]->GetSuffix();
        echo '<a href="https://www.qrz.com/db/'.$FullCallsign.'" class="pl" title="Click here to check the station on QRZ" target="_blank">'.$FullCallsign.'</a>';
        if ($Suffix) {
            echo ' - <i>'.$Suffix.'</i>';
        }
        echo '</td>
            <td align="center">';
        // Fetch database name
        $callsign = $Reflector->Nodes[$i]->GetCallSign();
        $userInfo = getUserData($callsign);
        echo $userInfo['name'];
        $connectTimestamp = $Reflector->Nodes[$i]->GetConnectTime();
        echo '</td>
            <td align="center">'.date("d/m/Y, H:i:s", $Reflector->Nodes[$i]->GetLastHeardTime()).'</td>
            <td align="center"><span class="live-duration" data-since="'.$connectTimestamp.'">'.FormatSeconds(time()-$connectTimestamp).'</span></td>
            <td align="center">'.$Reflector->Nodes[$i]->GetProtocol().'</td>
            <td align="center">'.$Reflector->Nodes[$i]->GetLinkedModule().'</td>';
        if ($PageOptions['RepeatersPage']['IPModus'] != 'HideIP') {
            echo '
            <td align="center">';
            $Bytes = explode(".", $Reflector->Nodes[$i]->GetIP());
            if ($Bytes !== false && count($Bytes) == 4) {
                switch ($PageOptions['RepeatersPage']['IPModus']) {
                    case 'ShowLast1ByteOfIP' : echo $PageOptions['RepeatersPage']['MasqueradeCharacter'].'.'.$PageOptions['RepeatersPage']['MasqueradeCharacter'].'.'.$PageOptions['RepeatersPage']['MasqueradeCharacter'].'.'.$Bytes[3]; break;
                    case 'ShowLast2ByteOfIP' : echo $PageOptions['RepeatersPage']['MasqueradeCharacter'].'.'.$PageOptions['RepeatersPage']['MasqueradeCharacter'].'.'.$Bytes[2].'.'.$Bytes[3]; break;
                    case 'ShowLast3ByteOfIP' : echo $PageOptions['RepeatersPage']['MasqueradeCharacter'].'.'.$Bytes[1].'.'.$Bytes[2].'.'.$Bytes[3]; break;
                    default : echo $Reflector->Nodes[$i]->GetIP();
                }
            }
            echo '</td>';
        }
        echo '
        </tr>';
    }
    if ($i == $PageOptions['RepeatersPage']['LimitTo']) { $i = $Reflector->NodeCount()+1; }
}

?>

</table>

<script>
function formatDuration(seconds) {
    var d = Math.floor(seconds / 86400);
    var h = Math.floor((seconds % 86400) / 3600);
    var m = Math.floor((seconds % 3600) / 60);
    var s = seconds % 60;
    if (d > 0) return d + "d " + String(h).padStart(2,"0") + ":" + String(m).padStart(2,"0") + ":" + String(s).padStart(2,"0");
    if (h > 0) return String(h).padStart(2,"0") + ":" + String(m).padStart(2,"0") + ":" + String(s).padStart(2,"0");
    return String(m).padStart(2,"0") + ":" + String(s).padStart(2,"0");
}

function tickDurations() {
    var now = Math.floor(Date.now() / 1000);
    document.querySelectorAll(".live-duration").forEach(function(el) {
        var since = parseInt(el.getAttribute("data-since"));
        el.textContent = formatDuration(now - since);
    });
}

setInterval(tickDurations, 1000);
tickDurations();
</script>
