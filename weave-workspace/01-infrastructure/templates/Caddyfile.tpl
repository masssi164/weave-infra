{
	admin off
}

${weave_site_addresses} {
	tls /certs/${tls_cert_filename} /certs/${tls_key_filename}
	encode zstd gzip

	@api path /api /api/*
	handle @api {
		reverse_proxy ${api_upstream}
	}

	@files path /files /files/*
	handle @files {
		respond "Weave files product route. Raw Nextcloud fallback: ${nextcloud_public_url}" 200
	}

	@calendar path /calendar /calendar/*
	handle @calendar {
		respond "Weave calendar product route. Calendar data is served through the Weave backend facade." 200
	}

	handle {
		respond "Weave local product gateway" 200
	}
}

${keycloak_site_addresses} {
	tls /certs/${tls_cert_filename} /certs/${tls_key_filename}
	encode zstd gzip

	reverse_proxy ${keycloak_upstream}
}

${matrix_site_addresses} {
	tls /certs/${tls_cert_filename} /certs/${tls_key_filename}
	encode zstd gzip

	@matrix_auth path_regexp matrix_auth ^/_matrix/client/(v1/auth_metadata|.*/(login|logout|refresh))$
	@matrix_client_well_known path /.well-known/matrix/client
	@synapse path /_matrix/* /_synapse/client/* /_synapse/mas/* /.well-known/matrix/*

	handle @matrix_auth {
		reverse_proxy ${mas_upstream}
	}

	handle @matrix_client_well_known {
		header Content-Type application/json
		respond `{"m.homeserver":{"base_url":"${matrix_public_url}"}}` 200
	}

	handle @synapse {
		reverse_proxy ${synapse_upstream}
	}

	handle {
		reverse_proxy ${mas_upstream}
	}
}

${nextcloud_site_addresses} {
	tls /certs/${tls_cert_filename} /certs/${tls_key_filename}
	encode zstd gzip

	reverse_proxy ${nextcloud_upstream}
}
