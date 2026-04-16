<?php
/**
 * Plugin Name: Merkos Hardening
 * Description: Reduz superfície de enumeração (REST users, sitemap, ?author), remove versão do WP dos headers/feeds.
 * Version: 1.0.0
 * Author: Merkos
 *
 * Carregado automaticamente do diretório mu-plugins — não pode ser desativado pelo admin.
 */

if (!defined('ABSPATH')) {
    exit;
}

// Bloqueia /wp-json/wp/v2/users (e /users/<id>) para quem não tem list_users.
// Admin autenticado continua enxergando — só fecha enumeração anônima.
add_filter('rest_endpoints', function ($endpoints) {
    if (current_user_can('list_users')) {
        return $endpoints;
    }
    foreach (array_keys($endpoints) as $route) {
        if (strpos($route, '/wp/v2/users') === 0) {
            unset($endpoints[$route]);
        }
    }
    return $endpoints;
});

// Remove o provider "users" do sitemap XML do core — /wp-sitemap-users-*.xml deixa de existir.
add_filter('wp_sitemaps_add_provider', function ($provider, $name) {
    return ($name === 'users') ? false : $provider;
}, 10, 2);

// Bloqueia /?author=N muito cedo — antes do redirect_canonical do WP expor o slug do autor.
add_action('parse_request', function ($wp) {
    if (isset($_GET['author']) || !empty($wp->query_vars['author']) || !empty($wp->query_vars['author_name'])) {
        wp_safe_redirect(home_url('/'), 301);
        exit;
    }
}, 1);

// Também zera a rewrite rule de author para nunca haver /author/<slug>/ válido.
add_filter('author_rewrite_rules', '__return_empty_array');

// Substitui o href de qualquer link pro archive do autor pela home.
// Evita que o slug (user_nicename) apareça em bylines renderizados pelo tema.
add_filter('author_link', function () {
    return home_url('/');
});

// /wp-sitemap-users-*.xml → 404 explícito (em vez de cair no catch-all renderizando home).
add_action('parse_request', function ($wp) {
    $uri = $_SERVER['REQUEST_URI'] ?? '';
    if (preg_match('#^/wp-sitemap-users-[^/]+\.xml$#', strtok($uri, '?'))) {
        status_header(404);
        nocache_headers();
        exit;
    }
}, 1);

// Remove a meta <generator> do <head> e o campo do RSS/Atom.
remove_action('wp_head', 'wp_generator');
add_filter('the_generator', '__return_empty_string');

// Esconde o display_name leakado via dc:creator do RSS quando for igual ao login.
// Se o autor não customizou o display_name, usa o nickname como fallback.
add_filter('the_author', function ($display_name) {
    $user = get_user_by('login', $display_name);
    if ($user && $user->nickname && $user->nickname !== $display_name) {
        return $user->nickname;
    }
    return $display_name;
});
