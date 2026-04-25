{
	admin off
}

${keycloak_site_addresses} {
	tls /certs/${tls_cert_filename} /certs/${tls_key_filename}
	encode zstd gzip

	reverse_proxy ${keycloak_upstream}
}

${nextcloud_site_addresses} {
	tls /certs/${tls_cert_filename} /certs/${tls_key_filename}
	encode zstd gzip

	reverse_proxy ${nextcloud_upstream}
}

${matrix_site_addresses} {
	tls /certs/${tls_cert_filename} /certs/${tls_key_filename}
	encode zstd gzip

	@matrix_auth_metadata path /_matrix/client/*/auth_metadata
	@matrix_auth path_regexp matrix_auth ^/_matrix/client/.*/(login|logout|refresh)$
	@synapse path /_matrix/* /_synapse/client/* /_synapse/mas/* /.well-known/matrix/*

	handle @matrix_auth_metadata {
		rewrite * /.well-known/openid-configuration
		reverse_proxy ${mas_upstream}
	}

	handle @matrix_auth {
		reverse_proxy ${mas_upstream}
	}

	handle @synapse {
		reverse_proxy ${synapse_upstream}
	}

	handle {
		reverse_proxy ${mas_upstream}
	}
}

${api_site_addresses} {
	tls /certs/${tls_cert_filename} /certs/${tls_key_filename}
	encode zstd gzip

	reverse_proxy ${api_upstream}
}
