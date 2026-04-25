server_name: "${matrix_homeserver}"
pid_file: /data/homeserver.pid
public_baseurl: "${matrix_public_url}/"

listeners:
  - port: 8008
    tls: false
    type: http
    x_forwarded: true
    resources:
      - names: [client]
        compress: false

database:
  name: psycopg2
  args:
    user: ${synapse_db_username}
    password: "${synapse_db_password}"
    database: ${synapse_db_name}
    host: ${synapse_db_host}
    port: ${synapse_db_port}
    cp_min: 5
    cp_max: 10

media_store_path: /data/media_store
report_stats: false
enable_registration: false
registration_shared_secret: "${synapse_registration_secret}"
macaroon_secret_key: "${synapse_macaroon_secret_key}"
form_secret: "${synapse_form_secret}"
signing_key_path: "/data/${matrix_homeserver}.signing.key"

trusted_key_servers:
  - server_name: "matrix.org"

matrix_authentication_service:
  enabled: true
  endpoint: "${mas_internal_endpoint}"
  secret: "${mas_matrix_secret}"
