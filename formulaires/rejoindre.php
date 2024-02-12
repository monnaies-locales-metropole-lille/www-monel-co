<?php

function formulaires_rejoindre_charger_dist(){
  $valeurs = array(
    'nom'=>'',
    'prenom'=>'',
    'societe'=>'',
    'email'=>'',
    'message'=>'');
	
	return $valeurs;
}

function formulaires_rejoindre_verifier_dist(){
	$erreurs = array();
	// check that mandatory fields are indeed filled out:
	foreach(array('nom','email','message') as $obligatoire)
		if (!_request($obligatoire)) $erreurs[$obligatoire] = 'Ce champ est obligatoire';
	
	// check that any entered email address is correctly formatted:
	include_spip('inc/filtres');
	if (_request('email') AND !email_valide(_request('email')))
		$erreurs['email'] = "Cette adresse email n'est pas valide";

	if (count($erreurs))
		$erreurs['message_erreur'] = 'Votre formulaire contient des erreurs!';
	return $erreurs;
}

function formulaires_rejoindre_traiter_dist(){
	$envoyer_mail = charger_fonction('envoyer_mail','inc');

  $from = 'Formulaire contact<ne-pas-repondre@monel.co>';
  $to = '<contact@monel.co>';
	$sujet = 'Nouveau contact sur le site www.monel.co';
  $fields = array('nom' => 'Nom', 'prenom' => 'Prénom', 'societe' => 'Société', 'email' => 'Email', 'message' => 'Message');


  $emailText = "Vous avez un nouveau message de votre formulaire contact\n======================================================\n";
  foreach ($fields as $key => $value) {
      // If the field exists in the $fields array, include it in the email 
      if (null != _request($key)) {
          $emailText .= "$value: " . _request($key) . "\n";
      }
  }

  // All the necessary headers for the email.
  $headers = array('Content-Type: text/plain; charset="UTF-8";',
      'Reply-To: ' . _request('email'),
      'Return-Path: ' . $from,
  );

	$envoyer_mail($to, $sujet, $emailText, $from, implode("\n", $headers));

	return array('message_ok'=>'Votre message a bien été pris en compte. Vous recevrez prochainement une réponse !');
}

?>
