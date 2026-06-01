import { describe, test, expect, vi, beforeEach } from 'vitest'
import type { Octokit } from '@octokit/rest'

// Mock @actions/core as a default export (matching the PR change from namespace to default import)
vi.mock('@actions/core', () => ({
  default: {
    info: vi.fn(),
    debug: vi.fn(),
    warning: vi.fn(),
    error: vi.fn(),
    setFailed: vi.fn(),
    setOutput: vi.fn(),
  },
}))

// Mock GitHub and action-context dependencies since we test main() directly
vi.mock('@/workflows/github', () => ({
  default: vi.fn(),
}))

vi.mock('@/workflows/action-context', () => ({
  getActionContext: vi.fn(),
}))

vi.mock('@/workflows/get-env-inputs', () => ({
  boolEnvVar: vi.fn(),
}))

import main from '../labeler'
import coreLib from '@actions/core'

const mockCore = vi.mocked(coreLib)

// Helper to create a minimal Octokit mock
function createMockOctokit(overrides: Record<string, any> = {}): Octokit {
  return {
    issues: {
      get: vi.fn(),
      addLabels: vi.fn(),
      removeLabel: vi.fn(),
      ...overrides,
    },
  } as unknown as Octokit
}

describe('labeler main()', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  describe('early exit conditions', () => {
    test('returns early when both addLabels and removeLabels are empty', async () => {
      const octokit = createMockOctokit()

      await main(coreLib, octokit, { addLabels: [], removeLabels: [] })

      expect(mockCore.info).toHaveBeenCalledWith(
        'No labels to add or remove specified, nothing to do.',
      )
      expect((octokit.issues.get as ReturnType<typeof vi.fn>)).not.toHaveBeenCalled()
    })

    test('returns early when addLabels and removeLabels are both undefined', async () => {
      const octokit = createMockOctokit()

      await main(coreLib, octokit, {})

      expect(mockCore.info).toHaveBeenCalledWith(
        'No labels to add or remove specified, nothing to do.',
      )
    })

    test('throws when issue_number is missing', async () => {
      const octokit = createMockOctokit()

      await expect(
        main(coreLib, octokit, {
          addLabels: ['bug'],
          owner: 'my-org',
          repo: 'my-repo',
        }),
      ).rejects.toThrow('Missing required parameters')
    })

    test('throws when owner is missing', async () => {
      const octokit = createMockOctokit()

      await expect(
        main(coreLib, octokit, {
          addLabels: ['bug'],
          issue_number: 42,
          repo: 'my-repo',
        }),
      ).rejects.toThrow('Missing required parameters')
    })

    test('throws when repo is missing', async () => {
      const octokit = createMockOctokit()

      await expect(
        main(coreLib, octokit, {
          addLabels: ['bug'],
          issue_number: 42,
          owner: 'my-org',
        }),
      ).rejects.toThrow('Missing required parameters')
    })
  })

  describe('ignoreIfAssigned', () => {
    test('skips labeling when ignoreIfAssigned is true and issue has assignees', async () => {
      const octokit = createMockOctokit()
      ;(octokit.issues.get as ReturnType<typeof vi.fn>).mockResolvedValue({
        data: {
          assignees: [{ login: 'user1' }],
          labels: [],
        },
      })

      const result = await main(coreLib, octokit, {
        addLabels: ['bug'],
        issue_number: 1,
        owner: 'org',
        repo: 'repo',
        ignoreIfAssigned: true,
      })

      expect(result).toBe(0)
      expect(mockCore.info).toHaveBeenCalledWith(
        expect.stringContaining('ignore-if-assigned is true'),
      )
      expect((octokit.issues.addLabels as ReturnType<typeof vi.fn>)).not.toHaveBeenCalled()
    })

    test('proceeds with labeling when ignoreIfAssigned is true but issue has no assignees', async () => {
      const octokit = createMockOctokit()
      ;(octokit.issues.get as ReturnType<typeof vi.fn>).mockResolvedValue({
        data: {
          assignees: [],
          labels: [],
        },
      })
      ;(octokit.issues.addLabels as ReturnType<typeof vi.fn>).mockResolvedValue({})

      await main(coreLib, octokit, {
        addLabels: ['bug'],
        issue_number: 1,
        owner: 'org',
        repo: 'repo',
        ignoreIfAssigned: true,
      })

      expect((octokit.issues.addLabels as ReturnType<typeof vi.fn>)).toHaveBeenCalledWith({
        issue_number: 1,
        owner: 'org',
        repo: 'repo',
        labels: ['bug'],
      })
    })

    test('throws when octokit.issues.get fails during ignoreIfAssigned check', async () => {
      const octokit = createMockOctokit()
      ;(octokit.issues.get as ReturnType<typeof vi.fn>).mockRejectedValue(
        new Error('API failure'),
      )

      await expect(
        main(coreLib, octokit, {
          addLabels: ['bug'],
          issue_number: 1,
          owner: 'org',
          repo: 'repo',
          ignoreIfAssigned: true,
        }),
      ).rejects.toThrow('Error getting issue')
    })
  })

  describe('ignoreIfLabeled', () => {
    test('skips labeling when ignoreIfLabeled is true and issue already has labels', async () => {
      const octokit = createMockOctokit()
      ;(octokit.issues.get as ReturnType<typeof vi.fn>).mockResolvedValue({
        data: {
          assignees: [],
          labels: [{ name: 'existing-label' }],
        },
      })

      const result = await main(coreLib, octokit, {
        addLabels: ['bug'],
        issue_number: 1,
        owner: 'org',
        repo: 'repo',
        ignoreIfLabeled: true,
      })

      expect(result).toBe(0)
      expect(mockCore.info).toHaveBeenCalledWith(
        expect.stringContaining('ignore-if-labeled is true'),
      )
      expect((octokit.issues.addLabels as ReturnType<typeof vi.fn>)).not.toHaveBeenCalled()
    })

    test('proceeds with labeling when ignoreIfLabeled is true but issue has no labels', async () => {
      const octokit = createMockOctokit()
      ;(octokit.issues.get as ReturnType<typeof vi.fn>).mockResolvedValue({
        data: {
          assignees: [],
          labels: [],
        },
      })
      ;(octokit.issues.addLabels as ReturnType<typeof vi.fn>).mockResolvedValue({})

      await main(coreLib, octokit, {
        addLabels: ['new-label'],
        issue_number: 5,
        owner: 'org',
        repo: 'repo',
        ignoreIfLabeled: true,
      })

      expect((octokit.issues.addLabels as ReturnType<typeof vi.fn>)).toHaveBeenCalledWith({
        issue_number: 5,
        owner: 'org',
        repo: 'repo',
        labels: ['new-label'],
      })
    })
  })

  describe('removing labels', () => {
    test('only removes labels that are already applied to the issue', async () => {
      const octokit = createMockOctokit()
      ;(octokit.issues.get as ReturnType<typeof vi.fn>).mockResolvedValue({
        data: {
          labels: [{ name: 'bug' }, { name: 'wontfix' }],
        },
      })
      ;(octokit.issues.removeLabel as ReturnType<typeof vi.fn>).mockResolvedValue({})

      await main(coreLib, octokit, {
        removeLabels: ['bug', 'not-applied'],
        issue_number: 1,
        owner: 'org',
        repo: 'repo',
      })

      // Only 'bug' should be removed (it's applied); 'not-applied' should be filtered out
      expect((octokit.issues.removeLabel as ReturnType<typeof vi.fn>)).toHaveBeenCalledTimes(1)
      expect((octokit.issues.removeLabel as ReturnType<typeof vi.fn>)).toHaveBeenCalledWith({
        issue_number: 1,
        owner: 'org',
        repo: 'repo',
        name: 'bug',
      })
      expect(mockCore.info).toHaveBeenCalledWith(expect.stringContaining('Removed labels: bug'))
    })

    test('skips removal entirely when no requested labels are applied', async () => {
      const octokit = createMockOctokit()
      ;(octokit.issues.get as ReturnType<typeof vi.fn>).mockResolvedValue({
        data: {
          labels: [{ name: 'other-label' }],
        },
      })

      await main(coreLib, octokit, {
        removeLabels: ['not-on-issue'],
        issue_number: 2,
        owner: 'org',
        repo: 'repo',
      })

      expect((octokit.issues.removeLabel as ReturnType<typeof vi.fn>)).not.toHaveBeenCalled()
    })

    test('handles string labels (not just label objects)', async () => {
      const octokit = createMockOctokit()
      ;(octokit.issues.get as ReturnType<typeof vi.fn>).mockResolvedValue({
        data: {
          // labels returned as plain strings
          labels: ['bug', 'enhancement'] as any,
        },
      })
      ;(octokit.issues.removeLabel as ReturnType<typeof vi.fn>).mockResolvedValue({})

      await main(coreLib, octokit, {
        removeLabels: ['bug'],
        issue_number: 3,
        owner: 'org',
        repo: 'repo',
      })

      expect((octokit.issues.removeLabel as ReturnType<typeof vi.fn>)).toHaveBeenCalledWith({
        issue_number: 3,
        owner: 'org',
        repo: 'repo',
        name: 'bug',
      })
    })

    test('throws when fetching issue fails during label removal', async () => {
      const octokit = createMockOctokit()
      ;(octokit.issues.get as ReturnType<typeof vi.fn>).mockRejectedValue(
        new Error('Network error'),
      )

      await expect(
        main(coreLib, octokit, {
          removeLabels: ['bug'],
          issue_number: 1,
          owner: 'org',
          repo: 'repo',
        }),
      ).rejects.toThrow('Error getting issue')
    })

    test('throws when removeLabel API call fails', async () => {
      const octokit = createMockOctokit()
      ;(octokit.issues.get as ReturnType<typeof vi.fn>).mockResolvedValue({
        data: {
          labels: [{ name: 'bug' }],
        },
      })
      ;(octokit.issues.removeLabel as ReturnType<typeof vi.fn>).mockRejectedValue(
        new Error('Permission denied'),
      )

      await expect(
        main(coreLib, octokit, {
          removeLabels: ['bug'],
          issue_number: 1,
          owner: 'org',
          repo: 'repo',
        }),
      ).rejects.toThrow('Error removing label')
    })
  })

  describe('adding labels', () => {
    test('adds labels to the issue', async () => {
      const octokit = createMockOctokit()
      ;(octokit.issues.addLabels as ReturnType<typeof vi.fn>).mockResolvedValue({})

      await main(coreLib, octokit, {
        addLabels: ['enhancement', 'good first issue'],
        issue_number: 10,
        owner: 'my-org',
        repo: 'my-repo',
      })

      expect((octokit.issues.addLabels as ReturnType<typeof vi.fn>)).toHaveBeenCalledWith({
        issue_number: 10,
        owner: 'my-org',
        repo: 'my-repo',
        labels: ['enhancement', 'good first issue'],
      })
      expect(mockCore.info).toHaveBeenCalledWith(
        expect.stringContaining('Added labels: enhancement, good first issue'),
      )
    })

    test('throws when addLabels API call fails', async () => {
      const octokit = createMockOctokit()
      ;(octokit.issues.addLabels as ReturnType<typeof vi.fn>).mockRejectedValue(
        new Error('Label not found'),
      )

      await expect(
        main(coreLib, octokit, {
          addLabels: ['nonexistent-label'],
          issue_number: 1,
          owner: 'org',
          repo: 'repo',
        }),
      ).rejects.toThrow('Error adding label')
    })
  })

  describe('combined add and remove operations', () => {
    test('both removes and adds labels in a single call', async () => {
      const octokit = createMockOctokit()
      ;(octokit.issues.get as ReturnType<typeof vi.fn>).mockResolvedValue({
        data: {
          labels: [{ name: 'old-label' }],
        },
      })
      ;(octokit.issues.removeLabel as ReturnType<typeof vi.fn>).mockResolvedValue({})
      ;(octokit.issues.addLabels as ReturnType<typeof vi.fn>).mockResolvedValue({})

      await main(coreLib, octokit, {
        addLabels: ['new-label'],
        removeLabels: ['old-label'],
        issue_number: 7,
        owner: 'org',
        repo: 'repo',
      })

      expect((octokit.issues.removeLabel as ReturnType<typeof vi.fn>)).toHaveBeenCalledWith({
        issue_number: 7,
        owner: 'org',
        repo: 'repo',
        name: 'old-label',
      })
      expect((octokit.issues.addLabels as ReturnType<typeof vi.fn>)).toHaveBeenCalledWith({
        issue_number: 7,
        owner: 'org',
        repo: 'repo',
        labels: ['new-label'],
      })
    })

    test('does not call addLabels API when only removeLabels is specified', async () => {
      const octokit = createMockOctokit()
      ;(octokit.issues.get as ReturnType<typeof vi.fn>).mockResolvedValue({
        data: {
          labels: [{ name: 'to-remove' }],
        },
      })
      ;(octokit.issues.removeLabel as ReturnType<typeof vi.fn>).mockResolvedValue({})

      await main(coreLib, octokit, {
        removeLabels: ['to-remove'],
        issue_number: 1,
        owner: 'org',
        repo: 'repo',
      })

      expect((octokit.issues.addLabels as ReturnType<typeof vi.fn>)).not.toHaveBeenCalled()
    })

    test('does not call removeLabel API when only addLabels is specified', async () => {
      const octokit = createMockOctokit()
      ;(octokit.issues.addLabels as ReturnType<typeof vi.fn>).mockResolvedValue({})

      await main(coreLib, octokit, {
        addLabels: ['new-label'],
        issue_number: 1,
        owner: 'org',
        repo: 'repo',
      })

      expect((octokit.issues.get as ReturnType<typeof vi.fn>)).not.toHaveBeenCalled()
      expect((octokit.issues.removeLabel as ReturnType<typeof vi.fn>)).not.toHaveBeenCalled()
    })
  })

  describe('default import compatibility', () => {
    test('main function is exported as default and callable', () => {
      // Verifies the module exports a default function (testing the import change from
      // `import * as coreLib` to `import coreLib` for @actions/core)
      expect(typeof main).toBe('function')
    })

    test('core.info is called when labels are added', async () => {
      const octokit = createMockOctokit()
      ;(octokit.issues.addLabels as ReturnType<typeof vi.fn>).mockResolvedValue({})

      await main(coreLib, octokit, {
        addLabels: ['test-label'],
        issue_number: 1,
        owner: 'org',
        repo: 'repo',
      })

      // Confirms coreLib (the default import) is used correctly as an object with .info()
      expect(mockCore.info).toHaveBeenCalled()
    })
  })
})
