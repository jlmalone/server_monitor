# Server Monitor Tests

## Running Tests

```bash
# Run all tests
npm test

# Run tests in watch mode (re-runs on file changes)
npm run test:watch

# Run with coverage report
npm run test:coverage
```

## Test Structure

### Unit Tests
- `config.test.js` - Tests config loading and service lookup
- `launchd.test.js` - Tests plist generation and launchd operations

### Integration Tests
- `integration.test.js` - Tests actual CLI commands and launchd interaction

## Test Philosophy

- **Unit tests**: Fast, no side effects, test individual functions
- **Integration tests**: Slower, interact with real launchd, verify CLI works end-to-end

## Adding New Tests

1. Create `test/yourmodule.test.js`
2. Import from `node:test` and `node:assert`
3. Follow existing patterns:

```javascript
import { describe, it } from 'node:test';
import assert from 'node:assert';

describe('your module', () => {
  it('should do something', () => {
    assert.strictEqual(1 + 1, 2);
  });
});
```

## CI/CD

Tests run automatically via Node.js built-in test runner (no external dependencies needed).
