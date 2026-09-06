// ports.mts — is something listening on a local port? Tries to connect on both loopback
// families: Docker Desktop publishes container ports on an IPv6 wildcard socket that still
// accepts IPv4, and a bind-based probe on 127.0.0.1 succeeds next to it, so binding would
// (and did) miss the compose Postgres on 5432.
import { connect } from "node:net";

function canConnect(host: string, port: number): Promise<boolean> {
  return new Promise((done) => {
    const socket = connect({ host, port });
    socket.setTimeout(500);
    socket.once("connect", () => { socket.destroy(); done(true); });
    socket.once("timeout", () => { socket.destroy(); done(false); });
    socket.once("error", () => done(false));
  });
}

export async function isPortBusy(port: number): Promise<boolean> {
  return (await canConnect("127.0.0.1", port)) || (await canConnect("::1", port));
}
