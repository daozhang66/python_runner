These localhost-only TLS fixtures are test resources. The private key is public
test data and is never loaded by production code. The test client trusts only
the fixture certificate through its injected SecurityContext; the production
client still uses the system trust store and rejects this server.

To regenerate (OpenSSL):

```text
openssl req -x509 -newkey rsa:2048 -nodes -keyout localhost-key.pem -out localhost-cert.pem -days 3650 -subj /CN=localhost -addext subjectAltName=DNS:localhost,IP:127.0.0.1
```
