export class FakeSnapshotAdapter {
  constructor(value) {
    this.value = structuredClone(value);
    this.reads = 0;
  }

  async snapshot() {
    this.reads += 1;
    return structuredClone(this.value);
  }
}

export class RecordingActionAdapter {
  constructor() {
    this.calls = [];
  }

  async execute(operation, parameters) {
    this.calls.push({ operation, parameters: structuredClone(parameters) });
    return { sequence: this.calls.length, operation };
  }
}
