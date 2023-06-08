<?php
/*
 *  CONFIGURE EVERYTHING HERE
 */

// an email address that will be in the From field of the email.
$from = 'Formulaire contact<ne-pas-repondre@monel.co>';

// an email address that will receive the email with the output of the form
$sendTo = '<contact@monel.co>';

// subject of the email
$subject = 'Nouveau contact sur le site www.monel.co';

// form field names and their translations.
// array variable name => Text to appear in the email
$fields = array('nom' => 'Nom', 'prenom' => 'Prénom', 'societe' => 'Société', 'email' => 'Email', 'message' => 'Message'); 

// message that will be displayed when everything is OK :)
$okMessage = 'Votre message a bien été transmis.<br>Nous vous contacterons dans les plus bref délais.';

// If something goes wrong, we will display this message.
$errorMessage = 'La soumission du formulaire a généré une erreur.<br>Svp veuillez reessayer plus tard ou contactez-nous directement à l\'adresse contact@monel.co';

/*
 *  LET'S DO THE SENDING
 */

// if you are not debugging and don't need error reporting, turn this off by error_reporting(0);
error_reporting(E_ALL & ~E_NOTICE);

try
{

    if(count($_POST) == 0) throw new \Exception('Form is empty');
            
    $emailText = "Vous avez un nouveau message de votre formulaire contact\n======================================================\n";

    foreach ($_POST as $key => $value) {
        // If the field exists in the $fields array, include it in the email 
        if (isset($fields[$key])) {
            $emailText .= "$fields[$key]: $value\n";
        }
    }

    // All the necessary headers for the email.
    $headers = array('Content-Type: text/plain; charset="UTF-8";',
        'From: ' . $from,
        'Reply-To: ' . $_POST['email'],
        'Return-Path: ' . $from,
    );
    
    // Send email
    mail($sendTo, $subject, $emailText, implode("\n", $headers));

    $responseArray = array('type' => 'success', 'message' => $okMessage);
}
catch (\Exception $e)
{
    $responseArray = array('type' => 'danger', 'message' => $errorMessage);
}


// if requested by AJAX request return JSON response
if (!empty($_SERVER['HTTP_X_REQUESTED_WITH']) && strtolower($_SERVER['HTTP_X_REQUESTED_WITH']) == 'xmlhttprequest') {
    $encoded = json_encode($responseArray);

    header('Content-Type: application/json');

    echo $encoded;
}
// else just display the message
else {
    echo $responseArray['message'];
}
