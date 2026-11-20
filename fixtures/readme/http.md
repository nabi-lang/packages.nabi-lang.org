# http

An HTTP/1.1 client and server built on `std::net`.

```nabi
fn main() throws {
    let res = try http::get("https://nabi-lang.org");
    println(f"{res.status}");
}
```
