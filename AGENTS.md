# Agent Guidelines for www-monel-co

## Build/Lint/Test Commands
- **Compile SCSS**: `sass scss/custom.scss css/custom-bootstrap.css`
- **No test suite** configured for this project
- **No linting** tools configured

## Project Overview
This is a static website built with HTML, CSS/SCSS, JavaScript (jQuery), and PHP (SPIP CMS), using devenv for local development with PHP 8.4, MySQL/MariaDB, and nginx.

## Code Style

### HTML
- SPIP template syntax: Use `[(#INCLURE{fond=...})]`, `<BOUCLE_...>`, and SPIP filters like `[(#DATE|affdate)]`
- Follow existing indentation (2 spaces)

### CSS/SCSS
- Variables defined in `css/_variables.scss` (e.g., `$dark-blue: #305780`)
- Use existing custom properties and Bootstrap overrides
- Keep selectors simple and semantic (e.g., `.tag-bleu-clair`, `.img-article-container`)

### JavaScript
- jQuery-based: Use `$(function() { ... })` for initialization
- AJAX pattern: Use `$.ajax()` with Bootstrap alert feedback
- Tab indentation, single quotes for strings

### PHP
- SPIP framework functions: `_request()`, `charger_fonction()`, `include_spip()`
- Form handlers follow SPIP pattern: `_charger_dist()`, `_verifier_dist()`, `_traiter_dist()`
- Tab indentation, single quotes preferred
