// Get the arrow:
let myarrow = document.getElementById("scrollback-arrow");

// When the user scrolls down 20px from the top of the document, show the arrow
window.onscroll = function() { scrollFunction() };

function scrollFunction() {
	minPixels = document.documentElement.scrollHeight / 3
	if (document.body.scrollTop > minPixels || document.documentElement.scrollTop > minPixels) {
		myarrow.style.display = "block";
	} else {
		myarrow.style.display = "none";
	}
}

// When the user clicks on the arrow, scroll to the top of the document
function topFunction() {
	document.body.scrollTop = 0; // For Safari
	document.documentElement.scrollTop = 0; // For Chrome, Firefox, IE and Opera
}
