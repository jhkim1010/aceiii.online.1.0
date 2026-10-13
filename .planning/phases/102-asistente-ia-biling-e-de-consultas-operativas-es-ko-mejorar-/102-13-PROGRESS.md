# 102-13 Progress

2026-10-13 09:42 ART — Task 1 DETENIDA antes del push (sin push, sin cambios en produccion).

Motivo: `git log --stat origin/main..HEAD` contiene commits ajenos a la fase 102:
- api-ventago `a2428263` feat(users): el admin de la tienda restablece la contrasena de su personal + cierra PUT /users/1 (users.controller/service + specs)
- ventago-app `7200d69f` feat(usuarios): «Restablecer contrasena» para el personal de la tienda (ResetClaveDialog, UsersListView, ResetClaveAdminDialog)

Esperados (autorizados): 800a3d35 y 14598fd8 en api; el resto son commits 102-xx.
Pendiente: decision del orquestador/usuario sobre si esos dos commits se despliegan con la fase o se aislan.
Task 2 y 3 no iniciadas.
