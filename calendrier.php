<?php
// Ajout d'un événement de l'agenda culturel au calendrier du téléphone
// (23/10/2026). L'appli iPhone/Android ne sait pas ouvrir un fichier .ics
// fabriqué sur place : elle ouvre cette adresse dans Safari/Chrome, qui reçoit
// le fichier et propose directement « Ajouter au calendrier ».
// Paramètre ?ics= : le contenu du fichier, encodé en base64 (URL-safe).

$raw = isset($_GET['ics']) ? (string) $_GET['ics'] : '';
$b64 = strtr($raw, '-_', '+/');
$b64 .= str_repeat('=', (4 - strlen($b64) % 4) % 4);
$ics = base64_decode($b64, true);

if ($ics === false || strlen($ics) > 8000 || strpos($ics, "BEGIN:VCALENDAR\r\n") !== 0 || substr(rtrim($ics), -13) !== 'END:VCALENDAR') {
  http_response_code(400);
  header('Content-Type: text/plain; charset=utf-8');
  echo "Événement introuvable.";
  exit;
}

header('Content-Type: text/calendar; charset=utf-8');
header('Content-Disposition: inline; filename="evenement-bligo.ics"');
header('Cache-Control: no-store');
echo $ics;
