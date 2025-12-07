# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

- **Compile SCSS**: `sass scss/custom.scss css/custom-bootstrap.css`
- **Start dev environment**: `devenv up` (runs nginx, PHP-FPM, and MariaDB)

## Development Environment

Uses [devenv](https://devenv.sh/) with:
- PHP 8.4 with php-fpm
- MariaDB (database: `monel`, user: `monel`, password: `monel`)
- nginx on port 80 for `monel.spip.local`

Add `127.0.0.1 monel.spip.local` to `/etc/hosts` for local development.

## Architecture

This is a website for Monel (a local business exchange network in Lille, France) built on **SPIP CMS**.

### Directory Structure
- Root level (`*.html`, `inclure/`, `formulaires/`, `css/`, `js/`) - Custom site templates (squelettes)
- `spip/` - SPIP CMS core installation
- `spip/squelettes-dist/` - SPIP default templates
- `spip/plugins-dist/` - SPIP bundled plugins
- `spip/plugins/auto/` - Additional installed plugins (e.g., scssphp, bootstrap4)

### SPIP Template Syntax
Templates use SPIP's squelette language:
- `#INCLURE{fond=inclure/nav}` - Include another template
- `#CHEMIN{img/logo.svg}` - Resolve asset path
- `<BOUCLE_nom(TABLE){criteres}>...</BOUCLE_nom>` - Database loops
- `[(#BALISE|filtre)]` - Tags with filters (e.g., `[(#DATE|affdate)]`)

### Styling
- Bootstrap 4 with custom overrides
- Variables in `css/_variables.scss` (primary color: `$dark-blue: #305780`)
- Theme mixins in `css/boot-theme.scss`
- Custom font: Fenwick (in `fonts/`)

## Code Style

### HTML/SPIP Templates
- 2 spaces indentation
- Use SPIP syntax for includes and dynamic content

### CSS/SCSS
- Use existing Bootstrap classes and custom variables
- Keep selectors semantic

### JavaScript
- jQuery-based, tab indentation, single quotes
- AJAX with Bootstrap alert feedback

### PHP (SPIP forms)
- SPIP form pattern: `_charger_dist()`, `_verifier_dist()`, `_traiter_dist()` functions
- Use `_request()` for form input, `include_spip()` for dependencies
