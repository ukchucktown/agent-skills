import { readFile } from "node:fs/promises";

export class JsonSnapshotAdapter {
  constructor(file) {
    this.file = file;
  }

  async snapshot() {
    return JSON.parse(await readFile(this.file, "utf8"));
  }
}
