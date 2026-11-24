<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Vehiculo extends Model
{
    use HasFactory;

    protected $table = 'vehiculos';

    protected $fillable = [
        'placa',
        'propietario',
        'categoria',
        'ejes',
        'saldo',
        'activo',
    ];

    protected $casts = [
        'ejes' => 'integer',
        'saldo' => 'decimal:2',
        'activo' => 'boolean',
    ];

    public function pasos()
    {
        return $this->hasMany(Paso::class, 'placa_normalizada', 'placa');
    }
}

