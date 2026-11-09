import React, { useEffect, useMemo, useState } from "react";

export interface CartLineProps {
    name: string;
    quantity: number;
    onRemove: (name: string) => void;
}

export interface StorefrontProps {
    title: string;
    lines: CartLineProps[];
}

interface StorefrontState {
    expanded: boolean;
}

export class CartTotal {
    private lines: CartLineProps[];

    constructor(lines: CartLineProps[]) {
        this.lines = lines;
    }

    quantity(): number {
        return this.lines.length;
    }
}

export function CartLine({ name, quantity, onRemove }: CartLineProps) {
    const [hovered, setHovered] = useState<boolean>(false);
    return (
        <li className="line" onMouseEnter={() => setHovered(true)}>
            <span>{name} x {quantity}</span>
            <button onClick={() => onRemove(name)}>{hovered ? "Remove" : "x"}</button>
        </li>
    );
}

export class Storefront extends React.Component<StorefrontProps, StorefrontState> {
    state: StorefrontState = { expanded: false };

    private toggle(): void {
        this.setState({ expanded: !this.state.expanded });
    }

    render() {
        const { title, lines } = this.props;
        return (
            <section>
                <h1 onClick={() => this.toggle()}>{title}</h1>
                <ul>
                    {lines.map((line) => (
                        <CartLine key={line.name} {...line} />
                    ))}
                </ul>
            </section>
        );
    }
}

export function useCartTotal(lines: CartLineProps[]): number {
    const total = useMemo(() => new CartTotal(lines).quantity(), [lines]);
    useEffect(() => {
        document.title = `${total} items`;
    }, [total]);
    return total;
}
