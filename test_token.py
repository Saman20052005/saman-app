import jwt
import datetime

# Use the default secret from config
SECRET_KEY = "change-me-in-production"
JWT_ALGORITHM = "HS256"

# Create token for test user
payload = {
    "email": "test@example.com",
    "exp": datetime.datetime.utcnow() + datetime.timedelta(hours=1),
    "iat": datetime.datetime.utcnow()
}

token = jwt.encode(payload, SECRET_KEY, algorithm=JWT_ALGORITHM)
print(f"Token: {token}")
