import Testing
@testable import TopophanySections

@Suite struct ProviderTests {
    /// topo sends a provider it knows in its own spelling, and any other as
    /// the topology wrote it; both find the same provider.
    @Test func knownByAnyName() {
        #expect(Provider.known("Cloudflare")?.key == "cloudflare")
        #expect(Provider.known("cloudflare")?.key == "cloudflare")
        #expect(Provider.known("Deno Deploy")?.key == "deno")
        #expect(Provider.known("deno-deploy")?.key == "deno")
        #expect(Provider.known("Fly.io")?.key == "fly")
        #expect(Provider.known("google")?.key == "gcp")
        #expect(Provider.known("Google Cloud")?.key == "gcp")
        #expect(Provider.known(" OCI ")?.key == "oracle")
        #expect(Provider.known("do")?.key == "digitalocean")
        #expect(Provider.known("vultr")?.key == "vultr")
        #expect(Provider.known("bandwagon")?.key == "bandwagonhost")
        #expect(Provider.known("阿里云")?.key == "alibaba")
        #expect(Provider.known("") == nil)
        #expect(Provider.known("--") == nil)
        #expect(Provider.known("my own rack") == nil)
        // Places are known too, as places: their glyph, not a company's logo.
        #expect(Provider.known("Home")?.isGeneric == true)
        #expect(Provider.known("on-prem")?.key == "office")
        #expect(Provider.known("Cloudflare")?.isGeneric == false)
    }

    @Test func spelledTheProvidersWay() {
        #expect(Provider.name("vultr") == "Vultr")
        #expect(Provider.name("digitalocean") == "DigitalOcean")
        #expect(Provider.name("bandwagon") == "BandwagonHost")
        #expect(Provider.name("Home") == "Home")
        #expect(Provider.name("homelab") == "homelab")
        #expect(Provider.name("my own rack") == "my own rack")
    }

    /// The sixteen topo knows, in its spelling (internal/view/edge.go).
    @Test func topoSpelling() {
        let topo = ["cloudflare": "Cloudflare", "vercel": "Vercel", "supabase": "Supabase", "gcp": "GCP", "azure": "Azure",
                    "aws": "AWS", "oracle": "Oracle", "deno": "Deno Deploy", "linode": "Linode", "digitalocean": "DigitalOcean",
                    "netlify": "Netlify", "fastly": "Fastly", "cloudfront": "CloudFront", "fly": "Fly.io", "render": "Render",
                    "railway": "Railway"]
        for (key, name) in topo { #expect(Provider.known(key)?.name == name, "\(key)") }
        // Every provider's own name finds it again.
        for p in Provider.all { #expect(Provider.known(p.name)?.key == p.key, "\(p.name)") }
    }
}
