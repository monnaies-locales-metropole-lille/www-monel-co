{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: {
  # https://devenv.sh/basics/
  # env.GREET = "devenv";

  # https://devenv.sh/packages/
  # packages = [ pkgs.git ];

  # https://devenv.sh/languages/
  # languages.rust.enable = true;
  languages.php = {
    enable = true;
    version = "8.4";
    extensions = [];

    ini = ''
      memory_limit = 512M
    '';

    # Configure php fpm pools for future use
    fpm.pools.web = {
      settings = {
        "pm" = "dynamic";
        "pm.max_children" = 5;
        "pm.start_servers" = 2;
        "pm.min_spare_servers" = 1;
        "pm.max_spare_servers" = 5;
      };
    };
  };

  # https://devenv.sh/processes/
  # processes.cargo-watch.exec = "cargo-watch";

  # https://devenv.sh/services/
  # services.postgres.enable = true;
  services.mysql = {
    enable = true;
    package = pkgs.mariadb;
    initialDatabases = [
      {name = "monel";}
    ];
    ensureUsers = [
      {
        name = "monel";
        password = "monel";
        ensurePermissions = {
          "monel.*" = "ALL PRIVILEGES";
        };
      }
    ];
  };

  services.nginx = {
    enable = true;
    httpConfig = ''
      server {
          listen       80;
          server_name  monel.spip.local;
          root         ${config.env.DEVENV_ROOT}/spip/;
          index        index.php index.html index.htm;
          client_max_body_size 10M;

          location ~ \.php {
              fastcgi_param  SCRIPT_FILENAME    $document_root$fastcgi_script_name;
              fastcgi_param  QUERY_STRING       $query_string;
              fastcgi_param  REQUEST_METHOD     $request_method;
              fastcgi_param  CONTENT_TYPE       $content_type;
              fastcgi_param  CONTENT_LENGTH     $content_length;
              fastcgi_param  SCRIPT_NAME        $fastcgi_script_name;
              fastcgi_param  REQUEST_URI        $request_uri;
              fastcgi_param  DOCUMENT_URI       $document_uri;
              fastcgi_param  DOCUMENT_ROOT      $document_root;
              fastcgi_param  SERVER_PROTOCOL    $server_protocol;
              fastcgi_param  REQUEST_SCHEME     $scheme;
              fastcgi_param  HTTPS              $https if_not_empty;
              fastcgi_param  GATEWAY_INTERFACE  CGI/1.1;
              fastcgi_param  SERVER_SOFTWARE    nginx/$nginx_version;
              fastcgi_param  REMOTE_ADDR        $remote_addr;
              fastcgi_param  REMOTE_PORT        $remote_port;
              fastcgi_param  SERVER_ADDR        $server_addr;
              fastcgi_param  SERVER_PORT        $server_port;
              fastcgi_param  SERVER_NAME        $server_name;
              # PHP only, required if PHP was built with --enable-force-cgi-redirect
              fastcgi_param  REDIRECT_STATUS    200;

              fastcgi_pass unix:${config.languages.php.fpm.pools.web.socket};
              fastcgi_split_path_info ^(.+\.php)(/.+)$;
              fastcgi_buffers 16 16k;
              fastcgi_buffer_size 32k;
          }

          location /IMG/ {
            try_files $uri /sites/$host$uri;
          }
          location /local/ {
            try_files $uri /sites/$host$uri;
          }
        }
    '';
  };

  # https://devenv.sh/scripts/
  # scripts.hello.exec = ''
  #   echo hello from $GREET
  # '';
  #
  # enterShell = ''
  #   php --version
  # '';

  # https://devenv.sh/tasks/
  # tasks = {
  #   "myproj:setup".exec = "mytool build";
  #   "devenv:enterShell".after = [ "myproj:setup" ];
  # };

  # https://devenv.sh/tests/
  # enterTest = ''
  #   echo "Running tests"
  #   # git --version | grep --color=auto "${pkgs.git.version}"
  #   php --version
  # '';

  # https://devenv.sh/git-hooks/
  # git-hooks.hooks.shellcheck.enable = true;

  # See full reference at https://devenv.sh/reference/options/
}
