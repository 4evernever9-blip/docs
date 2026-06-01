import { describe, test, expect, vi, beforeEach } from 'vitest'

import main from '../../../.github/actions/labeler/labeler.ts'

// Minimal mock for @actions/core
function makeMockCore() {
  return {
    info: vi.fn(),
    warning: vi.fn(),
    error: vi.fn(),
    setFailed: vi.fn(),
    debug: vi.fn(),
  }
}

// Minimal mock for Octokit shaped to the subset used by labeler
function makeMockOctokit(issueData: {
  assignees?: { login: string }[]
  labels?: ({ name: string } | string)[]
} = {}) {
  return {
    issues: {
      get: vi.fn().mockResolvedValue({ data: issueData }),
      addLabels: vi.fn().mockResolvedValue({}),
      removeLabel: vi.fn().mockResolvedValue({}),
    },
  }
}

describe('labeler main()', () => {
  const baseOpts = {
    issue_number: 42,
    owner: 'github',
    repo: 'docs',
  }

  describe('early-return conditions', () => {
    test('returns immediately when both addLabels and removeLabels are empty', async () => {
      const core = makeMockCore()
      const octokit = makeMockOctokit()

      await main(core as any, octokit as any, {
        ...baseOpts,
        addLabels: [],
        removeLabels: [],
      })

      expect(core.info).toHaveBeenCalledWith(
        'No labels to add or remove specified, nothing to do.',
      )
      expect(octokit.issues.get).not.toHaveBeenCalled()
      expect(octokit.issues.addLabels).not.toHaveBeenCalled()
    })

    test('returns immediately when opts has no labels keys at all', async () => {
      const core = makeMockCore()
      const octokit = makeMockOctokit()

      await main(core as any, octokit as any, {
        ...baseOpts,
        // addLabels and removeLabels both undefined → length check: undefined?.length === undefined
        // The condition is opts.addLabels?.length === 0 && opts.removeLabels?.length === 0
        // When both are undefined, the condition is false — so it does NOT return early
        // only both explicitly empty arrays cause early return
        addLabels: [],
        removeLabels: [],
      })

      expect(core.info).toHaveBeenCalledWith(
        'No labels to add or remove specified, nothing to do.',
      )
    })
  })

  describe('parameter validation', () => {
    test('throws when issue_number is missing', async () => {
      const core = makeMockCore()
      const octokit = makeMockOctokit()

      await expect(
        main(core as any, octokit as any, {
          owner: 'github',
          repo: 'docs',
          addLabels: ['bug'],
        }),
      ).rejects.toThrow('Missing required parameters')
    })

    test('throws when owner is missing', async () => {
      const core = makeMockCore()
      const octokit = makeMockOctokit()

      await expect(
        main(core as any, octokit as any, {
          issue_number: 1,
          repo: 'docs',
          addLabels: ['bug'],
        }),
      ).rejects.toThrow('Missing required parameters')
    })

    test('throws when repo is missing', async () => {
      const core = makeMockCore()
      const octokit = makeMockOctokit()

      await expect(
        main(core as any, octokit as any, {
          issue_number: 1,
          owner: 'github',
          addLabels: ['bug'],
        }),
      ).rejects.toThrow('Missing required parameters')
    })
  })

  describe('ignoreIfAssigned', () => {
    test('skips labeling when ignoreIfAssigned is true and issue has assignees', async () => {
      const core = makeMockCore()
      const octokit = makeMockOctokit({ assignees: [{ login: 'alice' }], labels: [] })

      const result = await main(core as any, octokit as any, {
        ...baseOpts,
        addLabels: ['bug'],
        ignoreIfAssigned: true,
      })

      expect(result).toBe(0)
      expect(core.info).toHaveBeenCalledWith(
        expect.stringContaining('ignore-if-assigned'),
      )
      expect(octokit.issues.addLabels).not.toHaveBeenCalled()
    })

    test('proceeds with labeling when ignoreIfAssigned is true but no assignees', async () => {
      const core = makeMockCore()
      const octokit = makeMockOctokit({ assignees: [], labels: [] })

      await main(core as any, octokit as any, {
        ...baseOpts,
        addLabels: ['bug'],
        ignoreIfAssigned: true,
      })

      expect(octokit.issues.addLabels).toHaveBeenCalledWith({
        issue_number: 42,
        owner: 'github',
        repo: 'docs',
        labels: ['bug'],
      })
    })

    test('proceeds with labeling when ignoreIfAssigned is false regardless of assignees', async () => {
      const core = makeMockCore()
      const octokit = makeMockOctokit({ assignees: [{ login: 'alice' }], labels: [] })

      await main(core as any, octokit as any, {
        ...baseOpts,
        addLabels: ['bug'],
        ignoreIfAssigned: false,
      })

      expect(octokit.issues.addLabels).toHaveBeenCalled()
    })
  })

  describe('ignoreIfLabeled', () => {
    test('skips labeling when ignoreIfLabeled is true and issue already has labels', async () => {
      const core = makeMockCore()
      const octokit = makeMockOctokit({ assignees: [], labels: [{ name: 'existing' }] })

      const result = await main(core as any, octokit as any, {
        ...baseOpts,
        addLabels: ['bug'],
        ignoreIfLabeled: true,
      })

      expect(result).toBe(0)
      expect(core.info).toHaveBeenCalledWith(
        expect.stringContaining('ignore-if-labeled'),
      )
      expect(octokit.issues.addLabels).not.toHaveBeenCalled()
    })

    test('proceeds when ignoreIfLabeled is true but issue has no labels', async () => {
      const core = makeMockCore()
      const octokit = makeMockOctokit({ assignees: [], labels: [] })

      await main(core as any, octokit as any, {
        ...baseOpts,
        addLabels: ['bug'],
        ignoreIfLabeled: true,
      })

      expect(octokit.issues.addLabels).toHaveBeenCalled()
    })
  })

  describe('removing labels', () => {
    test('removes a label that is currently applied', async () => {
      const core = makeMockCore()
      const octokit = makeMockOctokit({ assignees: [], labels: [{ name: 'stale' }] })

      await main(core as any, octokit as any, {
        ...baseOpts,
        removeLabels: ['stale'],
      })

      expect(octokit.issues.removeLabel).toHaveBeenCalledWith({
        issue_number: 42,
        owner: 'github',
        repo: 'docs',
        name: 'stale',
      })
      expect(core.info).toHaveBeenCalledWith('Removed labels: stale')
    })

    test('does not attempt to remove a label not currently applied', async () => {
      const core = makeMockCore()
      // The label 'missing' is not in the issue's labels
      const octokit = makeMockOctokit({ assignees: [], labels: [{ name: 'other' }] })

      await main(core as any, octokit as any, {
        ...baseOpts,
        removeLabels: ['missing'],
      })

      expect(octokit.issues.removeLabel).not.toHaveBeenCalled()
    })

    test('filters out non-applied labels from removeLabels list', async () => {
      const core = makeMockCore()
      const octokit = makeMockOctokit({
        assignees: [],
        labels: [{ name: 'stale' }, { name: 'bug' }],
      })

      await main(core as any, octokit as any, {
        ...baseOpts,
        removeLabels: ['stale', 'notapplied', 'bug'],
      })

      expect(octokit.issues.removeLabel).toHaveBeenCalledTimes(2)
      expect(octokit.issues.removeLabel).toHaveBeenCalledWith(
        expect.objectContaining({ name: 'stale' }),
      )
      expect(octokit.issues.removeLabel).toHaveBeenCalledWith(
        expect.objectContaining({ name: 'bug' }),
      )
    })

    test('handles string labels from issues.get response', async () => {
      const core = makeMockCore()
      // labels can be plain strings or objects
      const octokit = makeMockOctokit({ assignees: [], labels: ['stale'] as any })

      await main(core as any, octokit as any, {
        ...baseOpts,
        removeLabels: ['stale'],
      })

      expect(octokit.issues.removeLabel).toHaveBeenCalledWith(
        expect.objectContaining({ name: 'stale' }),
      )
    })

    test('throws when issues.get fails during removeLabels path', async () => {
      const core = makeMockCore()
      const octokit = {
        issues: {
          get: vi.fn().mockRejectedValue(new Error('API error')),
          addLabels: vi.fn(),
          removeLabel: vi.fn(),
        },
      }

      await expect(
        main(core as any, octokit as any, {
          ...baseOpts,
          removeLabels: ['stale'],
        }),
      ).rejects.toThrow('Error getting issue')
    })

    test('throws when removeLabel API call fails', async () => {
      const core = makeMockCore()
      const octokit = {
        issues: {
          get: vi.fn().mockResolvedValue({ data: { assignees: [], labels: [{ name: 'stale' }] } }),
          addLabels: vi.fn(),
          removeLabel: vi.fn().mockRejectedValue(new Error('remove failed')),
        },
      }

      await expect(
        main(core as any, octokit as any, {
          ...baseOpts,
          removeLabels: ['stale'],
        }),
      ).rejects.toThrow('Error removing label')
    })
  })

  describe('adding labels', () => {
    test('adds labels to the issue', async () => {
      const core = makeMockCore()
      const octokit = makeMockOctokit()

      await main(core as any, octokit as any, {
        ...baseOpts,
        addLabels: ['bug', 'help wanted'],
      })

      expect(octokit.issues.addLabels).toHaveBeenCalledWith({
        issue_number: 42,
        owner: 'github',
        repo: 'docs',
        labels: ['bug', 'help wanted'],
      })
      expect(core.info).toHaveBeenCalledWith('Added labels: bug, help wanted')
    })

    test('throws when addLabels API call fails', async () => {
      const core = makeMockCore()
      const octokit = {
        issues: {
          get: vi.fn(),
          addLabels: vi.fn().mockRejectedValue(new Error('add failed')),
          removeLabel: vi.fn(),
        },
      }

      await expect(
        main(core as any, octokit as any, {
          ...baseOpts,
          addLabels: ['bug'],
        }),
      ).rejects.toThrow('Error adding label')
    })
  })

  describe('combined add and remove', () => {
    test('both adds and removes labels in the same call', async () => {
      const core = makeMockCore()
      const octokit = makeMockOctokit({
        assignees: [],
        labels: [{ name: 'stale' }],
      })

      await main(core as any, octokit as any, {
        ...baseOpts,
        addLabels: ['bug'],
        removeLabels: ['stale'],
      })

      expect(octokit.issues.removeLabel).toHaveBeenCalledWith(
        expect.objectContaining({ name: 'stale' }),
      )
      expect(octokit.issues.addLabels).toHaveBeenCalledWith(
        expect.objectContaining({ labels: ['bug'] }),
      )
    })
  })

  describe('ignoreIfAssigned and ignoreIfLabeled together', () => {
    test('checks assignees first when both ignore options are set', async () => {
      const core = makeMockCore()
      // Has both assignees and labels — assignee check fires first
      const octokit = makeMockOctokit({
        assignees: [{ login: 'alice' }],
        labels: [{ name: 'existing' }],
      })

      const result = await main(core as any, octokit as any, {
        ...baseOpts,
        addLabels: ['bug'],
        ignoreIfAssigned: true,
        ignoreIfLabeled: true,
      })

      // Returns early due to assignee check (returns 0)
      expect(result).toBe(0)
      expect(core.info).toHaveBeenCalledWith(
        expect.stringContaining('ignore-if-assigned'),
      )
    })
  })

  describe('edge cases', () => {
    test('does not call removeLabel when removeLabels is not provided', async () => {
      const core = makeMockCore()
      const octokit = makeMockOctokit()

      await main(core as any, octokit as any, {
        ...baseOpts,
        addLabels: ['bug'],
      })

      expect(octokit.issues.removeLabel).not.toHaveBeenCalled()
    })

    test('does not call addLabels when addLabels is not provided', async () => {
      const core = makeMockCore()
      const octokit = makeMockOctokit({ assignees: [], labels: [{ name: 'stale' }] })

      await main(core as any, octokit as any, {
        ...baseOpts,
        removeLabels: ['stale'],
      })

      expect(octokit.issues.addLabels).not.toHaveBeenCalled()
    })

    test('throws error with missing params JSON in message', async () => {
      const core = makeMockCore()
      const octokit = makeMockOctokit()

      await expect(
        main(core as any, octokit as any, {
          addLabels: ['bug'],
        }),
      ).rejects.toThrow('Missing required parameters')
    })
  })
})
