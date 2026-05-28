<?php
/*
Possible values for IPModus
HideIP
ShowFullIP
ShowLast1ByteOfIP
ShowLast2ByteOfIP
ShowLast3ByteOfIP
*/

$Service     = array();
$CallingHome = array();
$PageOptions = array();
$VNStat      = array();

$PageOptions['ContactEmail']                         = 'your_email';	// Support E-Mail address
$PageOptions['CustomTXT']                            = 'custom_header'; // Custom text in your header
$PageOptions['Footnote']                             = 'custom_footnote'; // Custom text in you footnote
$PageOptions['DashboardVersion']                     = '3.2.1';		// Dashboard Version
$PageOptions['PageRefreshActive']                    = true;		// Activate automatic refresh
$PageOptions['PageRefreshDelay']                     = '3000';		// Page refresh time in miliseconds
$PageOptions['NumberOfModules']                      = MODQTD;		// Number of Modules enabled on reflector

$PageOptions['RepeatersPage'] = array();
$PageOptions['RepeatersPage']['LimitTo']             = 99;		// Number of Repeaters to show
$PageOptions['RepeatersPage']['IPModus']             = 'ShowLast3ByteOfIP';	// See possible options above
$PageOptions['RepeatersPage']['MasqueradeCharacter'] = '###';		// Character used for  masquerade

$PageOptions['PeerPage'] = array();
$PageOptions['PeerPage']['LimitTo']                  = 99;		// Number of peers to show
$PageOptions['PeerPage']['IPModus']                  = 'ShowLast3ByteOfIP';	// See possible options above
$PageOptions['PeerPage']['MasqueradeCharacter']      = '###';		// Character used for masquerade
$PageOptions['LastHeardPage']['LimitTo']             = 109;		// Number of stations to show

$PageOptions['ModuleNames'] = array();					          // Module nomination
$PageOptions['ModuleNames']['A']                     = 'Alpha';	// '<b>Link</b><br>XLXBRA-A';
$PageOptions['ModuleNames']['B']                     = 'Bravo';
$PageOptions['ModuleNames']['C']                     = 'Charlie';
$PageOptions['ModuleNames']['D']                     = 'Delta';
$PageOptions['ModuleNames']['E']                     = 'Echo Test';
$PageOptions['ModuleNames']['F']                     = 'Foxtrot';
$PageOptions['ModuleNames']['G']                     = 'Golf';
$PageOptions['ModuleNames']['H']                     = 'Hotel';
$PageOptions['ModuleNames']['I']                     = 'India';
$PageOptions['ModuleNames']['J']                     = 'Juliet';
$PageOptions['ModuleNames']['K']                     = 'Kilo';
$PageOptions['ModuleNames']['L']                     = 'Lima';
$PageOptions['ModuleNames']['M']                     = 'Mike';
$PageOptions['ModuleNames']['N']                     = 'November';
$PageOptions['ModuleNames']['O']                     = 'Oscsr';
$PageOptions['ModuleNames']['P']                     = 'Papa';
$PageOptions['ModuleNames']['Q']                     = 'Quebeq';
$PageOptions['ModuleNames']['R']                     = 'Romeo';
$PageOptions['ModuleNames']['S']                     = 'Sierra';
$PageOptions['ModuleNames']['T']                     = 'Tango';
$PageOptions['ModuleNames']['U']                     = 'Uniform';
$PageOptions['ModuleNames']['V']                     = 'Victor';
$PageOptions['ModuleNames']['W']                     = 'Whiskey';
$PageOptions['ModuleNames']['X']                     = 'X-ray';
$PageOptions['ModuleNames']['Y']                     = 'Yankee';
$PageOptions['ModuleNames']['Z']                     = 'Zulu';

$PageOptions['MetaDescription']                      = 'XLX is a D-Star Reflector System for Ham Radio Operators.';	// Meta Tag Values, usefull for Search Engine
$PageOptions['MetaKeywords']                         = 'Ham Radio, D-Star, XReflector, XLX, XRF, DCS, REF';		// Meta Tag Values, usefull for Search Engine
$PageOptions['MetaAuthor']                           = 'PP5PK';		// Meta Tag Values, usefull for Search Engine
$PageOptions['MetaRevisit']                          = 'After 3 Days';		// Meta Tag Values, usefull for Search Engine
$PageOptions['MetaRobots']                           = 'index,follow';		// Meta Tag Values, usefull for Search Engine

$PageOptions['Peers']['Show']                        = true;	// Show links whith other reflectors
$PageOptions['UserPage']['ShowFilter']               = true;	// Show Filter on Users page
$PageOptions['Traffic']['Show']                      = true;	// Enable vnstat traffic statistics
$PageOptions['IRCDDB']['Show']                       = true;	// Show D-Star live traffic status

$Service['PIDFile']                                  = '/var/log/xlxd.pid';
$Service['XMLFile']                                  = '/var/log/xlxd.xml';

$CallingHome['Active']                               = true;				// xlx phone home, true or false
$CallingHome['MyDashBoardURL']                       = 'http://your_dashboard';		// dashboard url
$CallingHome['ServerURL']                            = 'http://xlxapi.rlx.lu/api.php';	// database server, do not change !!!!
$CallingHome['PushDelay']                            = 300;				// push delay in seconds
$CallingHome['Country']                              = "your_country";			// Country
$CallingHome['Comment']                              = "your_comment";	// Comment. Max 100 character
$CallingHome['HashFile']                             = "/xlxd/callinghome.php";		// Make sure the apache user has read and write permissions in this folder.
$CallingHome['LastCallHomefile']                     = "/xlxd/lastcallhome.php";	// Path to lastcallhome file
$CallingHome['OverrideIPAddress']                    = "";		// Insert your IP address here. Leave blank for autodetection. No need to enter a fake address.
$CallingHome['InterlinkFile']                        = "/xlxd/xlxd.interlink";		// Path to interlink file

$VNStat['Interfaces']                                = array();
$VNStat['Interfaces'][0]['Name']                     = 'netact';  // Name of the interface that vnstat is using as default
$VNStat['Interfaces'][0]['Address']                  = 'netact';
$VNStat['Binary']                                    = '/usr/bin/vnstat';

/*
include an extra config file for people who dont like to mess with shipped config.ing.php
this makes updating dashboard from git a little bit easier
*/

if (file_exists("../config.inc.php")) {
 include ("../config.inc.php");
}

?>
