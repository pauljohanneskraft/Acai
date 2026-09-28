class Base {
public:
    virtual int rank();
};

class Sub : public Base {
public:
    int rank() override;
};
