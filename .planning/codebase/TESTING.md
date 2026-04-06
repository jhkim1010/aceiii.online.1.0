# Testing Patterns

**Analysis Date:** 2026-04-01

## Test Framework

**Runner (Backend):**
- Jest 29.7.0
- Config: inline in `api-ventago/package.json` under `"jest"` key
- SWC transform NOT used for tests (uses `ts-jest` instead)

**E2E Runner (Backend):**
- Jest 29.7.0 with separate config
- Config: `api-ventago/test/jest-e2e.json`
- Uses `ts-jest` transform
- Test regex: `.e2e-spec.ts$`

**Assertion Library:**
- Jest built-in (`expect`)
- Supertest for HTTP assertions (backend e2e)

**Frontend:**
- No test framework configured
- No test runner, no test scripts in `ventago-app/package.json`
- No test files exist in `ventago-app/src/`

**Run Commands:**
```bash
# Backend unit tests
cd api-ventago && npm test              # Run all .spec.ts tests
cd api-ventago && npm run test:watch    # Watch mode
cd api-ventago && npm run test:cov      # Coverage report

# Backend e2e tests
cd api-ventago && npm run test:e2e      # Run .e2e-spec.ts tests

# Backend debug mode
cd api-ventago && npm run test:debug    # Node inspector attached
```

## Test File Organization

**Location:**
- Unit tests: co-located pattern expected (`*.spec.ts` in `api-ventago/src/`)
- E2E tests: separate directory (`api-ventago/test/`)

**Naming:**
- Unit: `{name}.spec.ts` (configured regex: `.*\\.spec\\.ts$`)
- E2E: `{name}.e2e-spec.ts` (configured regex: `.e2e-spec.ts$`)

**Current test files:**
- `api-ventago/test/app.e2e-spec.ts` - single boilerplate e2e test (default NestJS scaffold)
- **ZERO unit test files exist** in `api-ventago/src/`
- **ZERO test files exist** in `ventago-app/src/`

## Test Structure

**E2E test pattern (only existing test):**
```typescript
// api-ventago/test/app.e2e-spec.ts
import { Test, TestingModule } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import * as request from 'supertest';
import { AppModule } from './../src/app.module';

describe('AppController (e2e)', () => {
  let app: INestApplication;

  beforeEach(async () => {
    const moduleFixture: TestingModule = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    await app.init();
  });

  it('/ (GET)', () => {
    return request(app.getHttpServer())
      .get('/')
      .expect(200)
      .expect('Hello World!');
  });
});
```

**Note:** This is the default NestJS scaffold test. It likely does NOT pass in the current state because the app has `api` prefix and the root route likely does not return "Hello World!".

## Jest Configuration

**Backend unit test config (`api-ventago/package.json`):**
```json
{
  "jest": {
    "moduleFileExtensions": ["js", "json", "ts"],
    "rootDir": "src",
    "testRegex": ".*\\.spec\\.ts$",
    "transform": {
      "^.+\\.(t|j)s$": "ts-jest"
    },
    "collectCoverageFrom": ["**/*.(t|j)s"],
    "coverageDirectory": "../coverage",
    "testEnvironment": "node"
  }
}
```

**Backend e2e config (`api-ventago/test/jest-e2e.json`):**
```json
{
  "moduleFileExtensions": ["js", "json", "ts"],
  "rootDir": ".",
  "testEnvironment": "node",
  "testRegex": ".e2e-spec.ts$",
  "transform": {
    "^.+\\.(t|j)s$": "ts-jest"
  }
}
```

## Mocking

**Framework:** Jest built-in mocking (available but unused)

**Available tools:**
- `@nestjs/testing` - `Test.createTestingModule()` for DI-aware test setup
- `supertest` - HTTP integration testing

**No established mocking patterns** exist in the codebase. If adding tests, follow NestJS standard patterns:
```typescript
// Example pattern for service testing
const module: TestingModule = await Test.createTestingModule({
  providers: [
    ProductsService,
    { provide: getModelToken(Product), useValue: mockProductModel },
  ],
}).compile();
```

## Coverage

**Requirements:** None enforced. No CI gates for coverage.

**View Coverage:**
```bash
cd api-ventago && npm run test:cov
# Output directory: api-ventago/coverage/
```

## Test Types

**Unit Tests:**
- Configuration exists in `api-ventago/package.json`
- **ZERO tests written** - only infrastructure is in place

**Integration Tests:**
- Not present

**E2E Tests:**
- One boilerplate file exists: `api-ventago/test/app.e2e-spec.ts`
- Likely broken (tests default NestJS root route, app uses `/api` prefix)

**Frontend Tests:**
- **Not configured at all** - no test framework, no test scripts, no test files
- `ventago-app/package.json` has no `test` script

## CI/CD Test Integration

**Jenkins pipeline:** Does NOT run tests as part of CI/CD.
- Frontend build: `docker compose build` -> `npm run build` (Next.js build only)
- Backend build: NestJS SWC build only
- **No test execution in deployment pipeline**

**Precheck script:** `scripts/precheck.sh` performs pre-deployment checks but does NOT run tests. It checks:
- Hoisted dependency compatibility for Docker
- (Other checks in script)

## Testing Gaps and Recommendations

**Critical gaps:**

1. **No unit tests for any backend service** - 50+ modules in `api-ventago/src/app/` with zero test coverage
   - Highest risk: `api-ventago/src/app/sales/` (financial transactions)
   - Highest risk: `api-ventago/src/app/session/` (security-critical authentication)
   - Highest risk: `api-ventago/src/app/production/` (BOM calculations)

2. **No frontend tests at all** - no framework configured, no test scripts
   - Framework recommendation: Vitest + React Testing Library (lighter than Jest for Next.js)

3. **No CI test gates** - Jenkins deploys without running any tests

4. **E2E test is broken boilerplate** - `api-ventago/test/app.e2e-spec.ts` tests a route that does not exist

**Priority for adding tests:**

| Priority | Area | Files | Rationale |
|----------|------|-------|-----------|
| P0 | CrudService | `api-ventago/src/common/crud/crud.service.ts` | Base class for all CRUD - high leverage |
| P0 | Auth service | `api-ventago/src/app/auth/auth.service.ts` | Security-critical |
| P0 | Session guard | `api-ventago/src/app/session/` | Anti-fraud system |
| P1 | Sales service | `api-ventago/src/app/sales/` | Financial accuracy |
| P1 | Stock service | `api-ventago/src/app/products/productStock.service.ts` | Inventory integrity |
| P2 | DTO validation | `api-ventago/src/app/*/dto/` | Input validation coverage |
| P3 | Frontend forms | `ventago-app/src/views/*/components/Modal*.tsx` | Form logic validation |

---

*Testing analysis: 2026-04-01*
