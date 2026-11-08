import React, { useState } from "react";

export class CartTotal {
    constructor(lines) {
        this.lines = lines;
    }

    quantity() {
        return this.lines.length;
    }
}

export function CartLine({ name, quantity, onRemove }) {
    const [hovered, setHovered] = useState(false);
    return (
        <li className="line" onMouseEnter={() => setHovered(true)}>
            <span>{name} x {quantity}</span>
            <button onClick={() => onRemove(name)}>{hovered ? "Remove" : "x"}</button>
        </li>
    );
}

export class Storefront extends React.Component {
    constructor(props) {
        super(props);
        this.state = { expanded: false };
        this.total = new CartTotal(props.lines);
    }

    toggle() {
        this.setState({ expanded: !this.state.expanded });
    }

    render() {
        return (
            <section>
                <h1 onClick={() => this.toggle()}>{this.props.title}</h1>
                <ul>
                    {this.props.lines.map((line) => (
                        <CartLine key={line.name} {...line} />
                    ))}
                </ul>
            </section>
        );
    }
}
