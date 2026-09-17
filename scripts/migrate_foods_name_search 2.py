import unicodedata

from backend.app.database import foods_collection


def normalize(text: str) -> str:
    return (
        unicodedata.normalize("NFD", text)
        .encode("ascii", "ignore")
        .decode("utf-8")
        .lower()
        .strip()
    )


def main() -> None:
    if foods_collection is None:
        print("foods_collection is None, database not available")
        return

    updated = 0
    for food in foods_collection.find({}):
        if "name_search" not in food:
            foods_collection.update_one(
                {"_id": food["_id"]},
                {"$set": {"name_search": normalize(food.get("name", ""))}},
            )
            updated += 1

    print(f"Updated {updated} foods with name_search field")


if __name__ == "__main__":
    main()

