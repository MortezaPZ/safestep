# Delivery note

Send these three files together:

1. `Hamghadam-source.zip` — current source (web, server, app)
2. `hamghadam.apk` — Android install (separate because it is about 180 MB)
3. `Hamghadam-rahnama.zip` — the letter, the install notes, and a short video

Changes in this build:

- Map tiles are served by the local server so the map is not blank when public tile servers are unreachable.
- The guardian role no longer has the support and settings entries.
- The mobile app is delivered as an installable file.

Run the web app on the computer:

```bash
cd backend
npm install
npm run seed
npm start
```

Then open `http://localhost:4080`.

Demo password for every seeded account: `Test@1234`.

- Primary user `09121110001`
- Guardian `09121110002`
- Admin `09121110009`

Install `hamghadam.apk` on the phone. The computer must be running the server. Phone and computer must share a Wi-Fi network. On the login screen set the server to `http://<computer-ipv4>:4080`. Read the address with `ipconfig`. `localhost` on the phone is the phone, not the computer.

Install steps are in `docs/mobile-client.md`. Short video: `docs/mobile-guide.mp4`.
