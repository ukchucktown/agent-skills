import assert from "node:assert/strict";
import test from "node:test";

import {
  applyPublishPlan,
  createPublishPlan,
} from "../../skills/engineering/sdlc-plan-work/scripts/lib/publisher.mjs";

const config = {
  featureLabel: "sdlc:feature",
  childLabel: "sdlc:child",
  readyLabel: "ready-for-agent",
};

const input = {
  schemaVersion: 1,
  mode: "feature",
  repository: "example/widgets",
  parent: { title: "Build widgets", body: "Approved specification." },
  children: [
    {
      key: "delivery",
      title: "Deliver widgets",
      body: "## Parent\n\n#{parent}\n",
      dependsOn: ["foundation"],
    },
    {
      key: "foundation",
      title: "Build the foundation",
      body: "## Parent\n\n#{parent}\n",
      dependsOn: [],
    },
  ],
};

class FakeIssueAdapter {
  constructor() {
    this.nextNumber = 100;
    this.byMarker = new Map();
    this.created = [];
    this.subIssues = new Set();
    this.blockers = new Set();
  }

  async findByMarker(repository, marker) {
    return structuredClone(this.byMarker.get(`${repository}:${marker}`) ?? null);
  }

  async createIssue(repository, issue) {
    const number = this.nextNumber++;
    const marker = issue.body.match(/<!-- agent-skills:sdlc-plan:[^>]+ -->/)[0];
    const created = {
      number,
      id: number * 10,
      title: issue.title,
      url: `https://example.test/issues/${number}`,
    };
    this.byMarker.set(`${repository}:${marker}`, created);
    this.created.push({ repository, issue: structuredClone(issue), ...created });
    return structuredClone(created);
  }

  async addSubIssue(repository, parent, childId) {
    this.subIssues.add(`${repository}:${parent}:${childId}`);
  }

  async addBlocker(repository, issue, blockerId) {
    this.blockers.add(`${repository}:${issue}:${blockerId}`);
  }
}

test("a feature plan sorts children by native dependency order", () => {
  const plan = createPublishPlan(input, config);
  assert.deepEqual(plan.children.map((child) => child.key), ["foundation", "delivery"]);
  assert.deepEqual(plan.parent.labels, ["sdlc:feature"]);
  assert.deepEqual(plan.children[0].labels, ["sdlc:child", "ready-for-agent"]);
  assert.deepEqual(plan.children[1].labels, ["sdlc:child"]);
  assert.match(plan.planId, /^[a-f0-9]{64}$/);
});

test("publishing is idempotent and links native subissues and blockers", async () => {
  const plan = createPublishPlan(input, config);
  const adapter = new FakeIssueAdapter();
  const first = await applyPublishPlan(plan, plan.planId, adapter);
  const second = await applyPublishPlan(plan, plan.planId, adapter);

  assert.equal(adapter.created.length, 3);
  assert.equal(adapter.subIssues.size, 2);
  assert.equal(adapter.blockers.size, 1);
  assert.equal(first.parent.number, second.parent.number);
  assert.deepEqual(
    first.children.map((child) => child.key),
    ["foundation", "delivery"],
  );
  assert.match(adapter.created[1].issue.body, /#100/);
});

test("publishing requires the exact approved plan ID", async () => {
  const plan = createPublishPlan(input, config);
  await assert.rejects(
    applyPublishPlan(plan, "different-plan", new FakeIssueAdapter()),
    /approved plan ID does not match/,
  );
  const tampered = structuredClone(plan);
  tampered.parent.labels = ["different-label"];
  await assert.rejects(
    applyPublishPlan(tampered, plan.planId, new FakeIssueAdapter()),
    /content does not match its planId/,
  );
});

test("planning rejects dependency cycles and unknown blockers", () => {
  const cycle = structuredClone(input);
  cycle.children[1].dependsOn = ["delivery"];
  assert.throws(() => createPublishPlan(cycle, config), /dependency cycle/);

  const unknown = structuredClone(input);
  unknown.children[0].dependsOn = ["missing"];
  assert.throws(() => createPublishPlan(unknown, config), /unknown blocker 'missing'/);
});

test("single-issue plans use no coordinated feature labels", async () => {
  const plan = createPublishPlan({
    schemaVersion: 1,
    mode: "single",
    repository: "example/widgets",
    issue: { title: "Fix one bug", body: "Approved outcome." },
  }, config);
  const adapter = new FakeIssueAdapter();
  const report = await applyPublishPlan(plan, plan.planId, adapter);
  assert.equal(report.mode, "single");
  assert.deepEqual(adapter.created[0].issue.labels, []);
});
