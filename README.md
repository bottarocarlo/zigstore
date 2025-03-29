# zigstore

A lightweight, in-memory key-value store written in Zig

## Usage

1. Clone the Repository
   ```
   git clone https://github.com/bottarocarlo/zigstore.git
   cd zigstore
   ```
2. Initialize a Zig Project
   ```
   zig init
   ```
3. Build & Run
   ```
   zig build run
   ```
4. CLI Commands
   ```
   > SET key value
   OK
   > GET key
   value
   > DEL key
   OK
   > EXIT
   ```
5. HTTP API

   Set a Key

   ```
   curl -X POST "http://127.0.0.1:8000/set?key=mykey&value=myvalue"
   ```

   Get a Key

   ```
   curl "http://127.0.0.1:8000/get?key=mykey"
   ```

   Delete a Key

   ```
   curl -X DELETE "http://127.0.0.1:8000/del?key=mykey"
   ```

## Notes

The server listens on `127.0.0.1:8000`.

The CLI runs alongside the HTTP server.

Memory management is handled via Zig's general-purpose allocator.
