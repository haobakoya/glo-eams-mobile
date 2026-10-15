Optional certificate pinning. Put your server's issuing CA (or intermediate) certificate here as
server_ca.pem. When present, the app trusts ONLY that certificate chain for all API calls, so a
rogue or intercepting certificate is rejected. Pin to the CA (not the server leaf certificate) so
routine certificate renewals do not break the app. If the file is absent, normal system trust is used.
