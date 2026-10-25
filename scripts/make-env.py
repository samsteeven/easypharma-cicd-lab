"""Crée .env avec des mots de passe aléatoires s'il n'existe pas (rien n'est affiché)."""
import pathlib
import secrets

env = pathlib.Path(__file__).resolve().parent.parent / '.env'
if env.exists():
    print('.env existe déjà : rien à faire')
else:
    env.write_text(
        f"JENKINS_ADMIN_PASSWORD={secrets.token_urlsafe(18)}\n"
        f"SONAR_ADMIN_PASSWORD=Sq{secrets.token_urlsafe(18)}9!\n"
        f"SONAR_DB_PASSWORD={secrets.token_hex(12)}\n"
        "SONAR_TOKEN=\n"
    )
    print('.env créé (valeurs aléatoires, ignoré par git)')
