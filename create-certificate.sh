#!/bin/bash
#
# Certificate generation script for AlmaLinux 8
# This script creates SSL/TLS certificates using easy-rsa
#

# Check if running as root
if [[ "$EUID" -ne 0 ]]; then
	echo "This script needs to be run with superuser privileges."
	exit 1
fi

# Check if running on AlmaLinux 8
if [[ ! -e /etc/almalinux-release ]]; then
	echo "This script is designed for AlmaLinux 8."
	exit 1
fi

os_version=$(grep -shoE '[0-9]+' /etc/almalinux-release | head -1)
if [[ "$os_version" -lt 8 ]]; then
	echo "AlmaLinux 8 or higher is required."
	exit 1
fi

# Install required packages
echo "Installing required packages..."
dnf install -y epel-release
dnf install -y openssl ca-certificates tar wget

# Set up easy-rsa directory
CERT_DIR="/root/certificates"
mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

# Download and extract easy-rsa
echo "Downloading easy-rsa..."
easy_rsa_url='https://github.com/OpenVPN/easy-rsa/releases/download/v3.2.4/EasyRSA-3.2.4.tgz'
if ! wget -qO- "$easy_rsa_url" | tar xz --strip-components 1; then
	echo "Failed to download or extract easy-rsa. Please check your internet connection."
	exit 1
fi

# Check if easyrsa exists and make it executable
if [[ ! -f ./easyrsa ]]; then
	echo "Error: easyrsa file not found after extraction."
	exit 1
fi
chmod +x ./easyrsa

# Initialize PKI
echo "Initializing PKI..."
./easyrsa --batch init-pki

# Get certificate details from user
echo ""
echo "=== Certificate Authority Setup ==="
read -p "Enter CA Common Name [My CA]: " ca_name
[[ -z "$ca_name" ]] && ca_name="My CA"

# Build CA
echo "Building Certificate Authority..."
./easyrsa --batch --req-cn="$ca_name" build-ca nopass

# Generate server certificate
echo ""
echo "=== Server Certificate ==="
read -p "Enter server name [server]: " server_name
[[ -z "$server_name" ]] && server_name="server"
echo "Generating server certificate..."
./easyrsa --batch --days=3650 build-server-full "$server_name" nopass

# Generate client certificates
echo ""
echo "=== Client Certificates ==="
read -p "How many client certificates do you want to generate? [1]: " num_clients
until [[ -z "$num_clients" || "$num_clients" =~ ^[0-9]+$ && "$num_clients" -gt 0 ]]; do
	echo "$num_clients: invalid number."
	read -p "How many client certificates do you want to generate? [1]: " num_clients
done
[[ -z "$num_clients" ]] && num_clients="1"

for ((i=1; i<=num_clients; i++)); do
	read -p "Enter client name [$i] [client$i]: " client_name
	[[ -z "$client_name" ]] && client_name="client$i"
	echo "Generating client certificate for $client_name..."
	./easyrsa --batch --days=3650 build-client-full "$client_name" nopass
done

# Generate CRL
echo "Generating Certificate Revocation List..."
./easyrsa --batch --days=3650 gen-crl

# Generate DH parameters
echo "Generating DH parameters (this may take a while)..."
./easyrsa gen-dh

# Generate TLS-Crypt key (optional, for OpenVPN)
echo "Generating TLS-Crypt key..."
./easyrsa gen-tls-crypt-key

# Set proper permissions
if [[ -d pki/private ]]; then
	chmod 600 pki/private/* 2>/dev/null
fi
if [[ -d pki/issued ]]; then
	chmod 644 pki/issued/* 2>/dev/null
fi
if [[ -f pki/ca.crt ]]; then
	chmod 644 pki/ca.crt
fi

# Summary
echo ""
echo "========================================"
echo "Certificate generation completed!"
echo "========================================"
echo ""
echo "Certificate directory: $CERT_DIR"
echo ""
echo "Files generated:"
echo "  CA Certificate:       pki/ca.crt"
echo "  CA Private Key:       pki/private/ca.key"
echo "  Server Certificate:   pki/issued/$server_name.crt"
echo "  Server Private Key:   pki/private/$server_name.key"
echo "  DH Parameters:        pki/dh.pem"
echo "  CRL:                  pki/crl.pem"
echo "  TLS-Crypt Key:        pki/private/easyrsa-tls.key"
echo ""
echo "Client certificates are in:"
echo "  Certificates:  pki/issued/client*.crt"
echo "  Private Keys:  pki/private/client*.key"
echo ""
echo "To revoke a certificate, run:"
echo "  cd $CERT_DIR && ./easyrsa revoke <client_name>"
echo "  cd $CERT_DIR && ./easyrsa gen-crl"
echo ""
