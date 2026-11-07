interface Named
interface Ranked

class Shelf<Item> where Item : Named, Item : Ranked {
    public fun put(item: Item): Int = 0
}
