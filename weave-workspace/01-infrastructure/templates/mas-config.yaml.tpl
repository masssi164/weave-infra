http:
  public_base: ${mas_public_url}/
  listeners:
    - name: web
      resources:
        - name: discovery
        - name: human
        - name: oauth
        - name: compat
        - name: graphql
        - name: assets
        - name: health
      binds:
        - address: "[::]:8080"

database:
  host: ${mas_db_host}
  port: ${mas_db_port}
  username: ${mas_db_username}
  password: ${mas_db_password}
  database: ${mas_db_name}
  ssl_mode: disable

matrix:
  kind: synapse
  homeserver: ${matrix_homeserver}
  endpoint: ${matrix_endpoint}
  secret: ${matrix_secret}

secrets:
  encryption: ${encryption_secret}
  keys:
    - kid: ${signing_key_kid}
      key_file: /config/signing.key

passwords:
  enabled: false

account:
  password_registration_enabled: false
  login_with_email_allowed: true

policy:
  data:
    client_registration:
      allow_insecure_uris: true

upstream_oauth2:
  providers:
    - id: ${upstream_provider_id}
      issuer: ${upstream_issuer}
      human_name: ${keycloak_human_name}
      client_id: ${upstream_client_id}
      client_secret: ${upstream_client_secret}
      token_endpoint_auth_method: client_secret_post
      scope: "openid email profile"
      discovery_mode: oidc
      pkce_method: auto
      fetch_userinfo: true
      claims_imports:
        localpart:
          action: require
          template: "{{ user.preferred_username or user.username or user.email.split('@')[0] }}"
          on_conflict: set
        displayname:
          action: force
          template: "{{ user.name or user.preferred_username or user.email }}"
        email:
          action: suggest
          template: "{{ user.email }}"
