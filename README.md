# PrismRTMPS: Secure, Self-hosted Multistreaming Solution (Fork)

[![Discord](https://img.shields.io/discord/1303046473985818654?label=Discord&logo=discord&style=for-the-badge)](http://wubu.waefrebeorn.com)

**CRITICAL SECURITY ADVISORY & PROJECT CONTEXT (Read First!)**

This project (`waefrebeorn/PrismRTMPS`) is a **fork** of the `MorrowShore/Prism` RTMP relay. It was created primarily to address a **critical security vulnerability** in the original version that allows for **stream hijacking**, and to provide ongoing maintenance and improvements.

*   **The Vulnerability (Original `MorrowShore/Prism` Pre-May 2025):** The original project historically lacked mandatory stream key validation (`on_publish` check). This meant if a server's IP address and port (usually 1935) were known, **anyone could stream to the server using *any* stream key**, and the original Prism would relay that unauthorized stream to all configured destinations (Twitch, YouTube, etc.).
*   **Attempted Contribution:** A Pull Request was submitted to `MorrowShore/Prism` with a robust fix for this vulnerability (implementing `on_publish` key validation via `stream_validator.py`). Unfortunately, this PR was closed by the original maintainer with comments focusing on the perceived use of AI in its generation and an unrelated, since-reverted funding file modification, rather than the technical merits of the security fix. Communication on the PR was subsequently limited.
*   **The "Fix" in Original `MorrowShore/Prism` (Post-May 7, 2025):** Following the closure of the PR, the original maintainer implemented their own changes. These changes include randomizing the RTMP application path (e.g., `rtmp://<ip>/<random_string>`). While this adds a minor layer of *obscurity*, it **does not fundamentally fix the stream hijacking vulnerability**. The random path is often logged and easily discoverable, and if found, hijacking is still possible because the stream key itself is *still not validated*. Their README continues to state "Your Stream Key Does Not Matter," and their commit messages for this "fix" reflect a focus on issues other than robust authentication.
*   **The Solution in This Fork (`waefrebeorn/PrismRTMPS`):** This fork implements **proper stream key validation**. When a stream connects, its key is checked against your configured destination keys. Only streams with a matching key are relayed. This is the industry-standard approach to securing RTMP relays.

**Recommendation:** Due to the persistent lack of true stream key validation in the `MorrowShore/Prism` repository, users concerned about stream security are strongly advised to use this fork (`waefrebeorn/PrismRTMPS`) or implement their own robust validation.

---

## Introduction (waefrebeorn/PrismRTMPS)

Would you like to stream to Twitch, YouTube, Kick, Trovo, Facebook, Instagram, X (Twitter), Cloudflare, and custom RTMP destinations at once, without the upload strain on your computer or recurring fees of commercial services?

You can host **PrismRTMPS** on a server to act as a **secure and efficient** prism for your streamed content!

You stream **one** high-quality feed to your PrismRTMPS server, and it will:
1.  **Validate** the incoming stream to ensure it's from you, preventing unauthorized access.
2.  **Relay** your stream to all the platforms you configure.

This fork also includes performance tuning (optimized `chunk_size`), updated core components for better stability and security, and active maintenance.

## Prequisites

You'd need a VPS server. Key considerations:
*   **Network Performance:** Good bandwidth, low latency, and stable routing between your VPS and your chosen streaming platforms are crucial, especially for 1080p 60fps.
*   **Resources:** A 2 vCore, 2GB RAM VPS (like those from Ionos, Linode, Digital Ocean, Vultr, Hetzner Cloud) is often sufficient. This fork has been tested and runs effectively on such configurations. Choose a location strategically.

## How To Set up `waefrebeorn/PrismRTMPS`

*   1- **SSH into your VPS server:**
    ```bash
    ssh root@<your_server_ip_address>
    ```

*   2- **Enter your password.**

*   3- **Install Docker & Git:**
    *   Follow the official Docker installation guide for your VPS's Linux distribution.
    *   Example for Debian/Ubuntu:
        ```bash
        sudo apt update && sudo apt install -y docker.io git
        sudo systemctl start docker
        sudo systemctl enable docker
        ```

*   4- **Clone and Build the PrismRTMPS image:**
    ```bash
    git clone https://github.com/waefrebeorn/PrismRTMPS.git
    cd PrismRTMPS
    docker build -t prism-rtmps . 
    ```
    *(Using `prism-rtmps` as the image name to differentiate)*

*   5- **Verify the image has been built:**
    ```bash
    docker images
    ```
    *(You should see `prism-rtmps` listed)*

*   6- **Run the PrismRTMPS Container:**
    *   Provide the specific stream keys for **each destination platform** you want to stream *to*.
    *   **IMPORTANT (Stream Key for OBS):** The key you use in OBS (Step 7) **must be ONE of the actual stream keys you provide below** (e.g., your `YOUTUBE_KEY`, `TWITCH_KEY`, etc.). This is how PrismRTMPS validates your stream.
    *   Remove lines for platforms you *don't* intend to use.

    **Example `docker run` command:**
    ```bash
    docker run -d --name prism-rtmps \
      -p 1935:1935 \
      -p 8081:8081 `# Expose port for RTMP stats page` \
      --restart unless-stopped `# Optional: auto-restart container` \
      # --- Provide stream keys for YOUR desired destinations ---
      # --- The key you use in OBS MUST match one of these ---
      -e YOUTUBE_KEY="your-youtube-stream-key" `# You could use this key in OBS` \
      -e TWITCH_URL="rtmp://live-iad.twitch.tv/app/" `# Find your nearest Twitch ingest server!` \
      -e TWITCH_KEY="your_twitch_stream_key" `# Or you could use this key in OBS` \
      -e KICK_KEY="sk_us-west-1_xxxxxxxxxxxxxx" `# Or this one...` \
      -e FACEBOOK_KEY="your-facebook-stream-key" \
      -e X_KEY="your_x_twitter_stream_key" \
      # -e INSTAGRAM_KEY="your-ig-key" ` # Uncomment if using Instagram ` \
      # -e CLOUDFLARE_KEY="your-cf-key" ` # Uncomment if using Cloudflare ` \
      # -e TROVO_KEY="your-trovo-key" `   # Uncomment if using Trovo ` \
      # -e RTMP1_URL="rtmp://custom.server.com/live" ` # Uncomment for Custom Dest 1 ` \
      # -e RTMP1_KEY="custom-key-1" `                  # Uncomment for Custom Dest 1 ` \
      prism-rtmps 
    ```
    *   The `-d` runs the container detached. `--restart unless-stopped` is recommended.
    *   **Note on Validator:** `stream_validator.py` in this fork checks the incoming key against *all* non-empty destination keys you provide.

*   7- **Configure OBS (or other streaming software):**
    *   Service: `Custom...`
    *   Server: `rtmp://<your_vps_ip_address>:1935/live`
        *(The application path is `/live` by default in this fork for simplicity and predictability)*
    *   Stream Key: **Use ONE of the actual stream keys you configured in the `docker run` command.**

*   8- **Begin streaming from OBS!**

*   9- **(Optional) View Stream Statistics:** Open `http://<your_vps_ip_address>:8081/stat` in your web browser.

We advise testing with one or two destinations first.

## How To Manage PrismRTMPS

*   **STOP** the container: `docker stop prism-rtmps`
*   **START** the container: `docker start prism-rtmps`
*   **VIEW LOGS:** `docker logs prism-rtmps` (or `docker logs -f prism-rtmps` for live logs)
*   **EDIT Destinations / Keys:** Stop, remove (`docker rm prism-rtmps`), and re-run the `docker run` command.
*   **UNINSTALL:** Stop, remove container, then `docker rmi prism-rtmps`.

## Troubleshooting Common Issues

*   **Lag / Falling Behind Stream:** Often a network bottleneck. This fork uses `chunk_size: 8192` for improved performance.
    *   **Diagnosis:** Test one destination at a time. Use `mtr <destination_hostname>` from VPS.
    *   **Solutions:** Different ingest servers, different VPS location, or lower stream bitrate.
*   **Stream Rejects / "Invalid Key":**
    *   OBS key *must exactly match* one key from `docker run`.
    *   Ensure at least one destination key is active in `docker run`.
    *   Check validator logs: `docker exec prism-rtmps tail /tmp/validator.log` or `docker logs prism-rtmps`.
*   **One Destination Not Working:** Check URL/Key in `docker run`. Check Nginx/Stunnel logs. Ensure stream is active on the platform.

## Support & Contributing to This Fork

Need help or have suggestions for **this fork**? Your contributions and feedback are welcome!

*   Raise an Issue: [https://github.com/waefrebeorn/PrismRTMPS/issues](https://github.com/waefrebeorn/PrismRTMPS/issues)
*   Join our Discord: [http://wubu.waefrebeorn.com](http://wubu.waefrebeorn.com) (Shield above also links here)

---
**Regarding the Original `MorrowShore/Prism` Repository:**

As noted in the advisory at the top, attempts to contribute essential security fixes to the original `MorrowShore/Prism` repository were met with dismissal and a subsequent "fix" that does not adequately address the core stream hijacking vulnerability. The maintainer's focus appeared to be on the perceived method of contribution rather than the critical security implications for users.

Given this, `waefrebeorn/PrismRTMPS` will serve as an actively maintained, secure, and performance-tuned alternative for the community. We encourage users to prioritize their security.
