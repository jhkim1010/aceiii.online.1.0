# Coding Conventions

**Analysis Date:** 2026-04-01

## Naming Patterns

**Files (Backend - NestJS):**
- Models: `{entity}.model.ts` (singular, camelCase) - e.g., `products.model.ts`, `branch.model.ts`
- Services: `{entity}.service.ts` - e.g., `products.service.ts`, `productStock.service.ts`
- Controllers: `{entity}.controller.ts` - e.g., `products.controller.ts`
- Modules: `{entity}.module.ts` - e.g., `products.module.ts`
- DTOs: `{action}-{entity}.dto.ts` - e.g., `create-products.dto.ts`, `updated-products.dto.ts`
- Interfaces: placed in `interfaces/` subdirectory within module
- Guards: placed in `guards/` subdirectory - e.g., `api-ventago/src/app/auth/guards/user-role.guard.ts`
- Decorators: placed in `decorators/` subdirectory - e.g., `api-ventago/src/app/auth/decorators/auth.decorator.ts`

**Files (Frontend - Next.js):**
- Pages: kebab-case directories with `index.tsx` - e.g., `ventago-app/src/pages/nueva-venta/index.tsx`
- Views: PascalCase components - e.g., `ventago-app/src/views/products/list/components/DataConfig.tsx`
- Modals: `Modal{Entity}.tsx` - e.g., `ModalDiscount.tsx`, `ModalStore.tsx`, `ModalBranch.tsx`
- DataConfig: `DataConfig.tsx` co-located with view components (contains columns + Yup schema + defaultValues)
- Services: `{name}.service.ts` - e.g., `ventago-app/src/services/api.service.ts`
- Hooks: `use{Name}.ts(x)` - e.g., `ventago-app/src/hooks/useAuth.tsx`

**Functions/Variables:**
- Use camelCase for all functions and variables
- React components use PascalCase
- Backend class names use PascalCase: `ProductsService`, `CrudController`

**Database Columns:**
- Sequelize models use camelCase: `imageUrl`, `isActive`, `storeId`
- DB columns are auto-mapped to snake_case via `underscored: true` global setting: `image_url`, `is_active`, `store_id`
- **CRITICAL:** When writing raw SQL, always use snake_case column names

**Types/Interfaces:**
- TypeScript interfaces/types use PascalCase: `DiscountForm`, `DataParams`
- DTOs use PascalCase with descriptive suffix: `CreateProductDto`, `UpdateProductStatusDto`
- Enums use PascalCase: `ValidRoles`, `ProductStatusSlug`

## Code Style

**Formatting (Backend - `api-ventago/.prettierrc`):**
- Single quotes: `true`
- Trailing comma: `all`
- No other overrides (Prettier defaults apply)

**Formatting (Frontend - `ventago-app/.prettierrc.js`):**
- Single quotes: `true`
- JSX single quotes: `true`
- No semicolons: `semi: false`
- Print width: `120`
- Trailing comma: `none`
- Arrow parens: `avoid`
- Tab width: `2`
- No tabs: `useTabs: false`

**Linting (Backend - `api-ventago/eslint.config.mjs`):**
- Flat config (ESLint 9)
- Extends: `eslint.configs.recommended`, `tseslint.configs.recommendedTypeChecked`, `eslint-plugin-prettier/recommended`
- `@typescript-eslint/no-explicit-any`: `off`
- `@typescript-eslint/no-floating-promises`: `warn`
- `@typescript-eslint/no-unsafe-argument`: `warn`

**Linting (Frontend - `ventago-app/.eslintrc.json`):**
- Extends: `next/core-web-vitals`, `plugin:@typescript-eslint/recommended`, `prettier`
- `@typescript-eslint/no-unused-vars`: `error` (BLOCKS BUILD)
- `@typescript-eslint/no-explicit-any`: `off`
- `@typescript-eslint/ban-ts-comment`: `off`
- `@typescript-eslint/no-empty-function`: `off`
- `@typescript-eslint/no-non-null-assertion`: `off`

## ESLint Rules That Block Builds (Frontend)

These rules are set to `error` and will **fail the production build**:

| Rule | Requirement | Example |
|------|-------------|---------|
| `newline-before-return` | Empty line before every `return` statement | Add blank line above `return` |
| `lines-around-comment` | Empty line before `//` and `/* */` comments | Add blank line above comments |
| `import/newline-after-import` | One blank line after the last import | Add blank line after imports |
| `@typescript-eslint/no-unused-vars` | All imports/variables must be used | Remove unused imports |

**Correct pattern:**
```typescript
import something from 'somewhere'

// This comment has a blank line above it
const value = something()

// Another comment with blank line above
return value
```

## Import Organization

**Order (Backend):**
1. NestJS core imports (`@nestjs/common`, `@nestjs/passport`)
2. Third-party imports (`sequelize`, `class-validator`)
3. Project imports using `src/` absolute paths (`src/common/crud/crud.service`)
4. Relative imports for same-module files (`./products.model`)

**Order (Frontend):**
1. React/Next.js imports
2. MUI imports (`@mui/material`)
3. Third-party imports (`react-hook-form`, `yup`)
4. Project imports using `src/` absolute paths (`src/@core/components/mui/text-field`)
5. Relative imports

**Path Aliases:**
- Backend: `src/` prefix for absolute paths (configured in `tsconfig.json`)
- Frontend: `src/` prefix for absolute paths (configured in `tsconfig.json`)
- No `@/` alias is used in this project

## Error Handling

**Backend Patterns:**

Use NestJS built-in HTTP exceptions:
```typescript
// In controllers/services
import { BadRequestException, NotFoundException, ConflictException, ForbiddenException } from '@nestjs/common';

throw new BadRequestException('Usuario no tiene tienda asignada');
throw new NotFoundException(`Registro con id ${id} no encontrado`);
```

Global exception filter catches all unhandled errors:
- Location: `api-ventago/src/common/filters/all-exceptions.filter.ts`
- Applied globally in `api-ventago/src/main.ts`
- 500+ errors: logged with stack trace via Winston
- 400+ errors: logged as warnings
- Returns JSON with `{ statusCode, message, error }` structure

Global validation pipe (applied in `api-ventago/src/main.ts`):
```typescript
new ValidationPipe({
  whitelist: true,
  forbidNonWhitelisted: true,
})
```

**Frontend Patterns:**

API errors are handled in `ventago-app/src/services/api.service.ts` interceptors:
- 401 with `SESSION_EXPIRED` code: clears session, redirects to `/login?reason=session_expired`
- 401/403 on non-login requests: calls `authService.logout()`, redirects to `/`
- Other errors: throws `new Error(error.response.data.message)` for caller to catch

View-level error handling uses try/catch with toast notifications:
```typescript
const onSubmit = async (data: FormType) => {
  try {
    await apiConnector.post('/endpoint', data)
    toast.success('Operacion exitosa')
  } catch (err: any) {
    toast.error(err.message || 'Error al procesar')
  }
}
```

## State Management (Redux Toolkit)

**Store:** `ventago-app/src/store/index.ts`
- Minimal Redux usage; only `user` slice is configured
- `serializableCheck: false` in middleware

**Pattern:** `createAsyncThunk` + `createSlice` in `ventago-app/src/store/apps/user/index.ts`

**Primary state approach:** Most data fetching is done directly via `apiConnector` in components, NOT through Redux. Redux is legacy/minimal.

**Typical data flow in views:**
```typescript
const [data, setData] = useState([])
const [loading, setLoading] = useState(false)

const fetchData = async () => {
  setLoading(true)
  try {
    const result = await apiConnector.get('/endpoint')
    setData(result.data)
  } catch (err) {
    toast.error('Error')
  } finally {
    setLoading(false)
  }
}
```

## Form Handling (React Hook Form + Yup)

**Two patterns exist:**

**Pattern 1: With Yup validation (complex forms)**
Used in: `ModalStore.tsx`, `ModalBranch.tsx`, `ModalUser.tsx`, `ModalPriceType.tsx`, etc.

Schema and defaults defined in co-located `DataConfig.tsx`:
```typescript
// DataConfig.tsx
import * as yup from 'yup';

export const schema = yup.object().shape({
  name: yup.string().required('El nombre es requerido'),
  cuit: yup.number().typeError('El CUIT debe ser un numero').required('El CUIT es requerido'),
})

export const defaultValues: any = {
  name: '',
  cuit: '',
}
```

Component usage:
```typescript
import { yupResolver } from '@hookform/resolvers/yup'
import { defaultValues, schema } from './DataConfig'

const { register, reset, handleSubmit, formState: { errors } } = useForm({
  resolver: yupResolver(schema),
  defaultValues: getInitialValues(),
  mode: 'onBlur',
})
```

**Pattern 2: Without Yup (simple forms)**
Used in: `ModalDiscount.tsx`, `ModalSeller.tsx`, etc.

```typescript
const { register, reset, handleSubmit, formState: { errors } } = useForm<FormType>({
  defaultValues,
  mode: 'onBlur',
})
```

**Edit mode pattern:** Check if entity prop exists to determine create vs. edit:
```typescript
const isEdit = Boolean(entity)

useEffect(() => {
  if (entity) {
    reset({ ...entity })  // populate form
  } else {
    reset(defaultValues)
  }
}, [entity])

const onSubmit = async (data: FormType) => {
  if (isEdit) {
    await apiConnector.put(`/endpoint/${entity.id}`, data)
  } else {
    await apiConnector.post('/endpoint', data)
  }
}
```

## API Service Patterns

**API connector:** `ventago-app/src/services/api.service.ts`

```typescript
import apiConnector from 'src/services/api.service'

// GET
const data = await apiConnector.get('/products/all', { page: 0, pageSize: 10 })

// POST
const result = await apiConnector.post('/products', payload)

// PUT
await apiConnector.put(`/products/${id}`, payload)

// DELETE
await apiConnector.remove(`/products/${id}`)

// File upload (POST)
const formData = new FormData()
formData.append('file', file)
await apiConnector.sendFile('/endpoint', formData)

// File upload (PUT)
await apiConnector.putFile('/endpoint', formData)
```

**Headers auto-injected by interceptor:**
- `Authorization: Bearer {token}` from localStorage
- `x-session-token: {sessionToken}` from localStorage
- `x-branch-id: {selectedBranchId}` from localStorage
- `x-api-key: 12345` (hardcoded)

## Component Patterns

**CustomTextField:** `ventago-app/src/@core/components/mui/text-field/index.tsx`
- Styled MUI TextField with custom border radius (12px) and label positioning
- Used throughout all forms:
```typescript
import CustomTextField from 'src/@core/components/mui/text-field'

<CustomTextField
  fullWidth
  label='Nombre'
  {...register('name')}
  error={Boolean(errors.name)}
  helperText={errors.name?.message}
/>
```

**FormDialog:** `ventago-app/src/components/dialogs/FormDialog.tsx`
- Reusable modal dialog wrapper with form submit handling
- Props: `open`, `onClose`, `title`, `children`, `onSubmit`, `titleAction`, `loading`, `size`, `isValid`
```typescript
import FormDialog from 'src/components/dialogs/FormDialog'

<FormDialog
  open={open}
  onClose={onClose}
  title={isEdit ? 'Editar' : 'Agregar'}
  titleAction={isEdit ? 'Guardar' : 'Agregar'}
  onSubmit={handleSubmit(onSubmit)}
  loading={loading}
>
  {/* form fields */}
</FormDialog>
```

**FullTable:** `ventago-app/src/components/table/FullTable.tsx`
- Wraps MUI `DataGrid` with Spanish locale, server-side pagination
- Props: `data`, `columns`, `paginationModel`, `rowSelected`, `setRowSelected`, `setPagination`, `loading`

**DataConfig pattern:** Co-locate table columns, Yup schema, and default values in `DataConfig.tsx` files:
- `ventago-app/src/views/{feature}/list/components/DataConfig.tsx` - columns + schema + defaultValues
- Column definitions use shared renderers from `ventago-app/src/components/table/columns.tsx`

**Toast notifications:** Use `react-hot-toast` for user feedback:
```typescript
import toast from 'react-hot-toast'
toast.success('Operacion exitosa')
toast.error('Error al procesar')
```

## Backend Module Pattern (NestJS)

**Standard module structure:**
```
api-ventago/src/app/{module}/
  {module}.module.ts      # Module definition
  {module}.controller.ts  # HTTP endpoints
  {module}.service.ts     # Business logic
  {module}.model.ts       # Sequelize model
  dto/                    # Data transfer objects
  interfaces/             # TypeScript interfaces
```

**CRUD base classes:** `api-ventago/src/common/crud/`
- `CrudService<T>` - provides `create`, `findAll`, `findOne`, `update`, `delete` with multi-tenant `storeId` filtering
- `CrudController<T>` - provides `getAll`, `getById`, `create`, `update`, `remove` endpoints

**Auth decorator:** `api-ventago/src/app/auth/decorators/auth.decorator.ts`
```typescript
@Auth(ValidRoles.admin, ValidRoles.superadmin, ValidRoles.vendedor, ValidRoles.gerente)
```
Combines `@RoleProtected()` + `@UseGuards(AuthGuard('jwt'), UserRoleGuard)`.

**Audit decorator:** `api-ventago/src/common/decorators/audit.decorator.ts`
Applied via `@Audit()` on controller methods, processed by `api-ventago/src/common/interceptors/audit.interceptor.ts` (global).

**DTO validation:** Use `class-validator` decorators with Spanish error messages:
```typescript
@IsString({ message: 'El nombre es requerido' })
readonly name: string;

@IsOptional()
@IsNumber()
readonly colorId?: number;
```

## Comment Language Conventions

- **Code comments:** Written in Korean (한국어) for implementation notes
- **User-facing strings:** Written in Spanish (error messages, UI labels, toast messages, DTO validation messages)
- **Variable/function names:** English
- **Examples:**
  - `// 빠른 판매용 제네릭 상품 조회` (Korean implementation comment)
  - `throw new BadRequestException('Usuario no tiene tienda asignada')` (Spanish error message)
  - `toast.success('Descuento creado correctamente')` (Spanish UI feedback)

## Multi-Tenant Data Access

**Every query must scope by `storeId`:**
```typescript
// Controller: get storeId from authenticated user
@GetUser() user: Users
if (!user.storeId) {
  throw new BadRequestException('Usuario no tiene tienda asignada')
}

// Service: filter by storeId
const result = await this.model.findAll({ where: { storeId: user.storeId } })
```

**CrudService handles this automatically** via optional `storeId` and `isSuperAdmin` parameters.

## Uppercase Input Helper

Use `withUppercase` for text inputs that should auto-capitalize:
```typescript
import { withUppercase } from 'src/utils/uppercase-input'

<CustomTextField {...withUppercase(register('name'))} />
```
Location: `ventago-app/src/utils/uppercase-input.ts`

---

*Convention analysis: 2026-04-01*
