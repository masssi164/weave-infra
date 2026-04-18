{
	admin off
}

https://${keycloak_public_host} {
	tls /certs/${tls_cert_filename} /certs/${tls_key_filename}
	encode zstd gzip

	reverse_proxy ${keycloak_upstream}
}

https://${nextcloud_public_host} {
	tls /certs/${tls_cert_filename} /certs/${tls_key_filename}
	encode zstd gzip

	reverse_proxy ${nextcloud_upstream}
}

https://${matrix_public_host} {
	tls /certs/${tls_cert_filename} /certs/${tls_key_filename}
	encode zstd gzip

	@matrix_auth path_regexp matrix_auth ^/_matrix/client/.*/(login|logout|refresh)$
	@synapse path /_matrix/* /_synapse/client/* /_synapse/mas/* /.well-known/matrix/*

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

https://${api_public_host} {
	tls /certs/${tls_cert_filename} /certs/${tls_key_filename}
	encode zstd gzip

	reverse_proxy ${api_upstream}
}
