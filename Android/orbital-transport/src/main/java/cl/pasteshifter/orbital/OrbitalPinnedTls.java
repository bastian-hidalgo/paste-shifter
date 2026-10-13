package cl.pasteshifter.orbital;

import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;
import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;

/** TLS 1.3 client context that trusts only the exact certificate fingerprint from pairing. */
public final class OrbitalPinnedTls {
    private OrbitalPinnedTls() {}

    public static SSLContext create(byte[] expectedFingerprintSha256) throws GeneralSecurityException {
        if (expectedFingerprintSha256 == null || expectedFingerprintSha256.length != 32) {
            throw new GeneralSecurityException("Invalid certificate pin");
        }
        X509TrustManager pinningTrustManager = new X509TrustManager() {
            @Override public void checkClientTrusted(X509Certificate[] chain, String authType)
                    throws CertificateException {
                throw new CertificateException("Orbital client certificates are not used");
            }

            @Override public void checkServerTrusted(X509Certificate[] chain, String authType)
                    throws CertificateException {
                if (chain == null || chain.length != 1) throw new CertificateException("Unexpected certificate chain");
                try {
                    if (!OrbitalProtocol.matchesCertificateFingerprint(chain[0], expectedFingerprintSha256)) {
                        throw new CertificateException("Mac certificate pin mismatch");
                    }
                    X509Certificate leaf = chain[0];
                    leaf.checkValidity();
                    if (leaf.getBasicConstraints() >= 0) throw new CertificateException("Mac identity is a CA certificate");
                    boolean[] keyUsage = leaf.getKeyUsage();
                    if (keyUsage == null || keyUsage.length == 0 || !keyUsage[0]) {
                        throw new CertificateException("Mac identity is not valid for TLS signing");
                    }
                    java.util.List<String> extendedUsage = leaf.getExtendedKeyUsage();
                    if (extendedUsage == null || !extendedUsage.contains("1.3.6.1.5.5.7.3.1")) {
                        throw new CertificateException("Mac identity is not valid for TLS server use");
                    }
                    leaf.verify(leaf.getPublicKey());
                } catch (GeneralSecurityException e) {
                    throw new CertificateException("Could not validate Mac certificate pin", e);
                }
            }

            @Override public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
        };
        SSLContext context = SSLContext.getInstance("TLSv1.3");
        context.init(null, new TrustManager[]{pinningTrustManager}, new SecureRandom());
        return context;
    }
}
