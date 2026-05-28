<?php
if (!isset($_SESSION['FilterCallSign'])) {
   $_SESSION['FilterCallSign'] = null;
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
            $_SESSION['FilterCallSign'] = "*".$_POST['txtSetCallsignFilter']."*";
            if (strpos($_SESSION['FilterCallSign'], "*") === false) {
               $_SESSION['FilterCallSign'] = "*".$_SESSION['FilterCallSign']."*";
            }
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
      $_SESSION['FilterCallSign'] = null;
   }
}


// Reads the log tail and returns ALL modules currently transmitting (not yet closed)
// Returns array keyed by module letter: ['D' => ['callsign' => 'PP5PK', 'since' => 1234567], ...]
function getAllActiveTx() {
    $logFile = '/var/log/xlx.log';
    if (!file_exists($logFile) || !is_readable($logFile)) return [];

    // Read last 16KB — enough to cover simultaneous TXs across modules
    $fp = fopen($logFile, 'r');
    fseek($fp, 0, SEEK_END);
    $size = ftell($fp);
    $chunk = min($size, 16384);
    fseek($fp, -$chunk, SEEK_END);
    $content = fread($fp, $chunk);
    fclose($fp);

    // Scan lines in reverse — first Opening found per module (without a Closing after it) = active TX
    $lines        = array_reverse(explode("\n", trim($content)));
    $closedModules = [];
    $activeTxMap   = [];

    foreach ($lines as $line) {
        if (preg_match('/Closing stream of module ([A-Z])/', $line, $m)) {
            // Mark module as closed (we're going backwards, so this closing comes AFTER an opening)
            if (!isset($closedModules[$m[1]])) {
                $closedModules[$m[1]] = true;
            }
            continue;
        }
        if (preg_match('/^(\d+) (\w+), (\d+:\d+:\d+): Opening stream on module ([A-Z]) for client (\S+)/', $line, $m)) {
            $module = $m[4];
            // Skip if already found (we only want the most recent opening per module)
            if (isset($activeTxMap[$module])) continue;
            // Skip if this opening was already closed
            if (isset($closedModules[$module])) {
                // Unmark so next opening of same module can be evaluated fresh
                unset($closedModules[$module]);
                continue;
            }
            $dateStr = $m[1] . ' ' . $m[2] . ' ' . date('Y') . ' ' . $m[3];
            $dt = DateTime::createFromFormat('d M Y H:i:s', $dateStr);
            if (!$dt) continue;
            // Ignore TX older than 5 minutes — log may have lost the Closing entry
            if ((time() - $dt->getTimestamp()) > 300) continue;
            $activeTxMap[$module] = [
                'callsign' => trim($m[5]),
                'since'    => $dt->getTimestamp(),
            ];
        }
    }
    return $activeTxMap;
}

// Function to get user data from SQLite database
function getUserData($callsign) {
    $dbFile = '/xlxd/users_db/users.db';
    try {
        $db = new SQLite3($dbFile);
    } catch (Exception $e) {
        return ['name' => '-', 'city_state' => '-'];
    }
    $callsign = strtoupper($callsign); // Ensure uppercase for matching
    $stmt = $db->prepare('SELECT name, city_state FROM users WHERE callsign = :callsign');
    $stmt->bindValue(':callsign', $callsign, SQLITE3_TEXT);
    $result = $stmt->execute();
    if ($row = $result->fetchArray(SQLITE3_ASSOC)) {
        // Separate city and state from city_state field using ", "
        $cityState = explode(', ', $row['city_state']);
        $cidade = trim($cityState[0]);
        $estado = isset($cityState[1]) ? trim($cityState[1]) : '';

        $data = [
            'name' => htmlspecialchars($row['name']),
            'city_state' => htmlspecialchars($cidade . ', ' . $estado)
        ];
    } else {
        $data = ['name' => '-', 'city_state' => '-'];
    }
    $db->close();
    return $data;
}
?>

<table border="0">
   <tr>
      <td valign="top">
         <table class="listingtable">
             <?php
             if ($PageOptions['UserPage']['ShowFilter']) {
                 echo '
                 <tr>
                    <th colspan="10">
                       <table width="100%" border="0">
                          <tr>
                             <td align="center">
                                <form name="frmFilterCallSign" method="post" action="./index.php">
                                   <input type="hidden" name="do" value="SetFilter" />
                                   <input type="text" class="FilterField" value="' . $_SESSION['FilterCallSign'] . '" name="txtSetCallsignFilter" placeholder="Callsign" onfocus="SuspendPageRefresh();" onblur="setTimeout(ReloadPage, ' . $PageOptions['PageRefreshDelay'] . ');" />
                                   <input type="submit" value="Apply" class="FilterSubmit" />
                                </form>
                             </td>';
                 if (($_SESSION['FilterModule'] != null) || ($_SESSION['FilterCallSign'] != null)) {
                     echo '
                        <td><a href="./index.php?do=resetfilter" class="smalllink">Disable Filters</a></td>';
                 }
                 echo '
                             <td align="center" style="padding-right:3px;">
                                <form name="frmFilterModule" method="post" action="./index.php">
                                   <input type="hidden" name="do" value="SetFilter" />
                                   <input type="text" class="FilterField" value="' . $_SESSION['FilterModule'] . '" name="txtSetModuleFilter" placeholder="Module" onfocus="SuspendPageRefresh();" onblur="setTimeout(ReloadPage, ' . $PageOptions['PageRefreshDelay'] . ');" />
                                   <input type="submit" value="Apply" class="FilterSubmit" />
                                </form>
                             </td>
                       </table>
                    </th>
                 </tr>';
             }
             ?>
             <tr>
                <th>Callsign</th>
                <th>Suffix</th>
                <th>Gateway</th>
                <th>Operator</th>
                <th>Origin</th>
                <th>Ctry</th>
                <th>Last Activity</th>
                <th>DPRS</th>
                <th align="center" valign="middle"><img src="./img/speaker.png" alt="Listening on" style="width: 18px;"/></th>
             </tr>
             <?php
             $Reflector->LoadFlags();
             $odd = "";
             // Detect all active TXs from log
             $activeTxMap = getAllActiveTx();
             // Replace log callsigns with the actual user callsign (first station of each module in the list)
             foreach ($activeTxMap as $module => &$txInfo) {
                 for ($s = 0; $s < $Reflector->StationCount(); $s++) {
                     if ($Reflector->Stations[$s]->GetModule() === $module) {
                         $txInfo['callsign'] = $Reflector->Stations[$s]->GetCallsignOnly();
                         break;
                     }
                 }
             }
             unset($txInfo);
             // For tab title: TX with least elapsed time (highest since = most recently started)
             $primaryTx = !empty($activeTxMap)
                 ? array_reduce($activeTxMap, function($carry, $item) {
                       return (!$carry || $item['since'] > $carry['since']) ? $item : $carry;
                   })
                 : null;
             $isTx       = ($primaryTx !== null);
             $txSince    = $isTx ? $primaryTx['since'] : 0;
             $txCallsign = $isTx ? $primaryTx['callsign'] : '';
             $checkedModules = []; // track first occurrence per module
             for ($i = 0; $i < $Reflector->StationCount(); $i++) {
                 $ShowThisStation = true;
                 if ($PageOptions['UserPage']['ShowFilter']) {
                     $CS = true;
                     if ($_SESSION['FilterCallSign'] != null) {
                         if (!fnmatch($_SESSION['FilterCallSign'], $Reflector->Stations[$i]->GetCallSign(), FNM_CASEFOLD)) {
                             $CS = false;
                         }
                     }
                     $MO = true;
                     if ($_SESSION['FilterModule'] != null) {
                         if (trim(strtolower($_SESSION['FilterModule'])) != strtolower($Reflector->Stations[$i]->GetModule())) {
                             $MO = false;
                         }
                     }
                     $ShowThisStation = ($CS && $MO);
                 }
                 if ($ShowThisStation) {
                     if ($odd == "#252525") { $odd = "#2c2c2c"; } else { $odd = "#252525"; }
                     // TX highlight only on the first occurrence of each module in the list
                     $stationModule = $Reflector->Stations[$i]->GetModule();
                     $isFirstOfModule = !isset($checkedModules[$stationModule]);
                     if ($isFirstOfModule) $checkedModules[$stationModule] = true;
                     $rowTxInfo = ($isFirstOfModule && isset($activeTxMap[$stationModule])) ? $activeTxMap[$stationModule] : null;
                     $rowIsTx   = ($rowTxInfo !== null);
                     $rowSince  = $rowIsTx ? $rowTxInfo['since'] : 0;
                     $rowBg     = $rowIsTx ? "#4a2000" : $odd;
                     $rowClass  = $rowIsTx ? " class=\"tx-active\"" : "";
                     echo '
                 <tr height="30" bgcolor="' . $rowBg . '"' . $rowClass . ' onMouseOver="this.bgColor=\'#586553\';" onMouseOut="this.bgColor=\'' . $rowBg . '\'">
                    <td width="80" align="center"><a href="https://www.qrz.com/db/' . $Reflector->Stations[$i]->GetCallsignOnly() . '" class="pl" title="Click here to check the QRZ for this callsign" target="_blank">' . $Reflector->Stations[$i]->GetCallsignOnly() . '</a></td>
                    <td width="50" align="center">' . $Reflector->Stations[$i]->GetSuffix() . '</td>';
                     // Fetch user data from SQLite database
                     $callsign = $Reflector->Stations[$i]->GetCallsignOnly();
                     $userInfo = getUserData($callsign);
                     echo '
                    <td width="90" align="center">' . $Reflector->Stations[$i]->GetVia();
                     if ($Reflector->Stations[$i]->GetPeer() != $Reflector->GetReflectorName()) {
                         echo ' / ' . $Reflector->Stations[$i]->GetPeer();
                     }
                     echo '</td>
                    <td width="220" align="center">' . $userInfo['name'] . '</td>
                    <td width="200" align="center">' . $userInfo['city_state'] . '</td>
                    <td align="center" width="40" valign="middle">';
                     list ($Flag, $Name) = $Reflector->GetFlag($Reflector->Stations[$i]->GetCallSign());
                     if (file_exists("./img/flags/" . $Flag . ".png")) {
                         echo '<a href="#" class="tip"><img src="./img/flags/' . $Flag . '.png" height="15" alt="' . $Name . '" /><span>' . $Name . '</span></a>';
                     }
                     echo '</td>
                    <td width="170" align="center">' . ($rowIsTx
                        ? '<span class="tx-timer" data-since="' . $rowSince . '" style="color:#ffaa44;font-weight:bold;">TXing 00:00s</span>'
                        : @date("d/m/Y, H:i:s", $Reflector->Stations[$i]->GetLastHeardTime())) . '</td>
                    <td width="40" align="center" valign="middle">';
                      if ($rowIsTx) {
                          echo '<img src="./img/tx.gif" style="margin-top:3px;" height="20"/>';
                      } else {
                          echo '<a href="http://www.aprs.fi/' . $Reflector->Stations[$i]->GetCallsignOnly() . '" class="pl" title="Click here to check the location of the device" target="_blank"><img src="./img/satellite.png" style="width: 40%;"/></a>';
                      }
                      echo '</td>
                    <td align="center" width="30" valign="middle">' . $Reflector->Stations[$i]->GetModule() . '</td>
                 </tr>';
                 }
                 if ($i == $PageOptions['LastHeardPage']['LimitTo']) { $i = $Reflector->StationCount() + 1; }
             }
             ?>
         </table>
      </td>
   </tr>
</table>
<table class="listingtable" width="900px">
   <?php
   $Modules = $Reflector->GetModules();
   sort($Modules, SORT_STRING);
   for ($i = 0; $i < count($Modules); $i++) {
       // Fetch users for this module to get the count
       $Users = $Reflector->GetNodesInModulesByID($Modules[$i]);
       $userCount = count($Users);
       echo '<tr>';
       if (isset($PageOptions['ModuleNames'][$Modules[$i]])) {
           echo '<th>Module ' . $Modules[$i] . ' | ' . $PageOptions['ModuleNames'][$Modules[$i]] . ' (' . $userCount . ')</th>';
       } else {
           echo '<th>Module ' . $Modules[$i] . ' | ' . $Modules[$i] . ' (' . $userCount . ')</th>';
       }
       echo '</tr>';
       echo '<tr>';
       echo '<td style="border:0px;padding:0px;padding-bottom:10px;">';
       echo '<div style="display: flex; flex-wrap: wrap; gap: 5px; justify-content: center;">';
       $odd = "";
       $UserCheckedArray = array();
       for ($j = 0; $j < count($Users); $j++) {
           $Displayname = $Reflector->GetCallsignAndSuffixByID($Users[$j]);
           echo '<div style="border: 1px solid #444444; display: inline-block;">';
           echo '<a href="http://www.aprs.fi/' . $Displayname . '" class="pl" title="Click here to check the location of the station" target="_blank" style="background-color: ' . ($odd == "#252525" ? "#242424" : "#252525") . '; padding: 2px 5px; margin: 2px; display: inline-block;">' . $Displayname . '</a>';
           echo '</div>';
           $odd = ($odd == "#252525") ? "#242424" : "#252525";
           $UserCheckedArray[] = $Users[$j];
       }
       echo '</div>';
       echo '</td>';
       echo '</tr>';
   }
   ?>
</table>

<script>
(function() {
    // Primary TX for tab title (most recently started)
    var txSince    = <?php echo json_encode($isTx ? $txSince : null); ?>;
    var txCallsign = <?php echo json_encode($isTx ? $txCallsign : ''); ?>;

    function formatTx(since) {
        var elapsed = Math.floor(Date.now() / 1000) - since;
        var m = Math.floor(elapsed / 60);
        var s = elapsed % 60;
        return 'TXing ' + String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0') + 's';
    }

    function updateTabTitle(txStr) {
        var connected  = document.querySelector('#menubar a[href*="repeaters"]');
        var countMatch = connected ? connected.textContent.match(/\((\d+)\)/) : null;
        var stations   = countMatch ? '(' + countMatch[1] + ')' : '';
        var base       = '<?php echo addslashes($PageOptions['CustomTXT']); ?>';
        if (txStr && txCallsign) {
            document.title = stations + ' ' + txCallsign + ' ' + txStr + '...';
        } else {
            document.title = stations ? stations + ' ' + base : base;
        }
    }

    function tick() {
        // Each tx-timer row has its own data-since — update independently
        document.querySelectorAll('.tx-timer').forEach(function(el) {
            var since = parseInt(el.getAttribute('data-since'));
            el.textContent = formatTx(since);
        });
        // Tab title uses the primary (most recent) TX
        updateTabTitle(txSince ? formatTx(txSince) : null);
    }

    // Clear any previous interval left by AJAX reload
    if (window.txTimerInterval) {
        clearInterval(window.txTimerInterval);
        window.txTimerInterval = null;
    }

    // Signal to updateTitle() whether TX is active
    window.txActive = !!txSince;

    tick();
    window.txTimerInterval = setInterval(tick, 1000);
})();
</script>
